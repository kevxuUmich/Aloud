import CryptoKit
import Foundation
import KokoroBundle
import Testing

@testable import Kokoro

/// A downloader a test drives by hand: it records what it was asked and delivers
/// progress, a finished file or a failure when told to.
@MainActor final class FakeDownloader: KokoroDownloading {
    struct Request { let url: URL; let destination: URL; let resumeData: Data? }
    var requests: [Request] = []
    var cancels = 0
    var running = false
    weak var delegate: (any KokoroDownloadDelegate)?
    var destination: URL?

    nonisolated init() {}
    func download(_ url: URL, to destination: URL, resumeData: Data?, delegate: any KokoroDownloadDelegate) {
        requests.append(Request(url: url, destination: destination, resumeData: resumeData))
        self.delegate = delegate
        self.destination = destination
    }
    func reattach(to destination: URL, delegate: any KokoroDownloadDelegate) async -> Bool {
        guard running else { return false }
        self.delegate = delegate
        self.destination = destination
        return true
    }
    func cancel() { cancels += 1 }

    func progress(_ f: Double) { delegate?.downloadProgressed(f) }
    func finish(with data: Data) throws {
        try data.write(to: destination!)
        delegate?.downloadFinished()
    }
    func fail(_ failure: KokoroDownloadFailure, resumeData: Data? = nil) {
        delegate?.downloadFailed(failure, resumeData: resumeData)
    }
}

@Suite @MainActor struct KokoroStoreTests {
    func scratch() throws -> URL {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        return url
    }

    /// A real, tiny archive of a bundle-shaped tree, and the release that pins it.
    func makeArchive() throws -> (data: Data, release: KokoroReleaseInfo) {
        let tree = try scratch()
        try FileManager.default.createDirectory(
            at: tree.appendingPathComponent("voices"), withIntermediateDirectories: true)
        try Data("{\"schema_version\": 1}\n".utf8).write(
            to: tree.appendingPathComponent("KokoroRuntimeManifest.json"))
        try Data(count: 1024).write(to: tree.appendingPathComponent("voices/af_bella.bin"))
        let archive = try scratch().appendingPathComponent("kokoro-1.aar")
        try AppleArchiveFile.compress(directory: tree, to: archive)
        let data = try Data(contentsOf: archive)
        let sha = SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined()
        let release = KokoroReleaseInfo(
            url: URL(string: "https://example.invalid/kokoro-1.aar")!, version: "1", sha256: sha,
            bytes: Int64(data.count))
        return (data, release)
    }

    func make(release: KokoroReleaseInfo) throws -> (KokoroStore, FakeDownloader, KokoroPaths) {
        let root = try scratch()
        let paths = KokoroPaths(
            support: root.appendingPathComponent("support"), caches: root.appendingPathComponent("caches"))
        let downloader = FakeDownloader()
        let store = KokoroStore(paths: paths, release: release, downloader: downloader)
        return (store, downloader, paths)
    }

    func install(_ store: KokoroStore) async {
        await store.installTask?.value
    }

    @Test func aFreshStoreIsAbsent() async throws {
        let (store, _, _) = try make(release: try makeArchive().release)
        await store.start()
        #expect(store.state == .absent)
        #expect(!store.isInstalledNow)
        #expect(store.installedRoot == nil)
    }

    /// The whole happy path: download reports progress, the file matches, it is
    /// extracted into place, the marker is written last, and the store says installed.
    @Test func aMatchingDownloadIsInstalled() async throws {
        let (data, release) = try makeArchive()
        let (store, downloader, paths) = try make(release: release)
        await store.start()
        var installed = 0
        store.onInstalled = { installed += 1 }

        store.download()
        #expect(downloader.requests.map(\.url) == [release.url])
        #expect(downloader.requests.first?.destination == paths.archive)
        #expect(store.state == .downloading(0))
        downloader.progress(0.4)
        #expect(store.state == .downloading(0.4))
        try downloader.finish(with: data)
        #expect(store.state == .installing)
        await install(store)

        guard case .installed(let version, let bytes) = store.state else {
            Issue.record("expected installed, got \(store.state)")
            return
        }
        #expect(version == "1")
        #expect(bytes == 1024 + 22)
        #expect(store.isInstalledNow)
        #expect(installed == 1)
        #expect(store.installedRoot == paths.modelDirectory(version: "1"))
        #expect(FileManager.default.fileExists(atPath: paths.marker(version: "1").path))
        #expect(
            FileManager.default.fileExists(
                atPath: paths.modelDirectory(version: "1").appendingPathComponent("voices/af_bella.bin").path)
        )
        #expect(!FileManager.default.fileExists(atPath: paths.archive.path))
        #expect(!FileManager.default.fileExists(atPath: paths.installing.path))
        #expect(FileManager.default.fileExists(atPath: paths.compiledCache(version: "1").path))
    }

    /// A file that does not hash to the pinned value is deleted and reported; nothing
    /// is extracted, and the resume data that fetched it goes too, so Retry starts over
    /// instead of resuming the same bad bytes for ever.
    @Test func aMismatchedDownloadIsDeletedAndFails() async throws {
        let (data, release) = try makeArchive()
        let (store, downloader, paths) = try make(release: release)
        await store.start()
        store.download()
        // A dropped connection first, so there is resume data for the retry to reuse.
        downloader.fail(.offline, resumeData: Data("partial".utf8))
        store.download()
        #expect(downloader.requests.last?.resumeData == Data("partial".utf8))

        var wrong = data
        wrong[wrong.count - 1] ^= 0xFF
        try downloader.finish(with: wrong)
        await install(store)
        #expect(store.state == .failed("The download did not match what Aloud expected."))
        #expect(!FileManager.default.fileExists(atPath: paths.archive.path))
        #expect(!FileManager.default.fileExists(atPath: paths.modelDirectory(version: "1").path))
        #expect(!store.isInstalledNow)

        #expect(!FileManager.default.fileExists(atPath: paths.resumeData.path))
        store.download()
        #expect(downloader.requests.last?.resumeData == nil)
    }

    /// The disk is measured before the checksum and the extraction, so a full disk is a
    /// sentence rather than a write failure halfway through unpacking.
    @Test func notEnoughDiskSpaceIsSaidBeforeExtracting() async throws {
        let (data, release) = try makeArchive()
        let root = try scratch()
        let paths = KokoroPaths(
            support: root.appendingPathComponent("support"), caches: root.appendingPathComponent("caches"))
        let downloader = FakeDownloader()
        let store = KokoroStore(
            paths: paths, release: release, downloader: downloader, availableBytes: { _ in 1 })
        await store.start()
        store.download()
        try downloader.finish(with: data)
        await install(store)
        #expect(store.state == .failed("Not enough disk space."))
        #expect(!FileManager.default.fileExists(atPath: paths.archive.path))
        #expect(!FileManager.default.fileExists(atPath: paths.modelDirectory(version: "1").path))
        #expect(!store.isInstalledNow)
    }

    @Test func downloadFailuresAreSaidInOneSentence() async throws {
        let (store, downloader, _) = try make(release: try makeArchive().release)
        await store.start()
        store.download()
        downloader.fail(.offline)
        #expect(store.state == .failed("No internet connection."))
        store.download()
        downloader.fail(.http(404))
        #expect(store.state == .failed("The server answered 404."))
        store.download()
        downloader.fail(.other("boom"))
        #expect(store.state == .failed("boom"))
    }

    /// A dropped connection leaves resume data, and the retry hands it back to the
    /// downloader so the bytes already fetched are not fetched again.
    @Test func retryResumesFromResumeData() async throws {
        let (store, downloader, paths) = try make(release: try makeArchive().release)
        await store.start()
        store.download()
        downloader.fail(.offline, resumeData: Data("partial".utf8))
        #expect(try Data(contentsOf: paths.resumeData) == Data("partial".utf8))
        store.download()
        #expect(downloader.requests.last?.resumeData == Data("partial".utf8))
    }

    /// Cancel is the reader's, not a failure: the task is cancelled, the resume data
    /// dropped, and the store is back where it started.
    @Test func cancelReturnsToAbsent() async throws {
        let (store, downloader, paths) = try make(release: try makeArchive().release)
        await store.start()
        store.download()
        downloader.progress(0.5)
        store.cancel()
        #expect(downloader.cancels == 1)
        #expect(store.state == .absent)
        #expect(!FileManager.default.fileExists(atPath: paths.resumeData.path))
        // A late callback from the cancelled task changes nothing.
        downloader.progress(0.9)
        #expect(store.state == .absent)
    }

    @Test func removeDeletesTheVersionAndItsCache() async throws {
        let (data, release) = try makeArchive()
        let (store, downloader, paths) = try make(release: release)
        await store.start()
        store.download()
        try downloader.finish(with: data)
        await install(store)
        store.remove()
        #expect(store.state == .absent)
        #expect(!store.isInstalledNow)
        #expect(!FileManager.default.fileExists(atPath: paths.modelDirectory(version: "1").path))
        #expect(!FileManager.default.fileExists(atPath: paths.compiledCache(version: "1").path))
    }

    /// A remove while the install is still running wins: the install stops at its
    /// cancellation check, and anything it had already put in place goes with its
    /// discarded outcome, so nothing is left half-installed.
    @Test func removeDuringInstallLeavesNothing() async throws {
        let (data, release) = try makeArchive()
        let (store, downloader, paths) = try make(release: release)
        await store.start()
        store.download()
        try downloader.finish(with: data)
        store.remove()
        await install(store)
        #expect(store.state == .absent)
        #expect(!store.isInstalledNow)
        #expect(!FileManager.default.fileExists(atPath: paths.modelDirectory(version: "1").path))
        #expect(!FileManager.default.fileExists(atPath: paths.compiledCache(version: "1").path))
        #expect(!FileManager.default.fileExists(atPath: paths.installing.path))
    }

    /// Remove during a download stops the download rather than leaving it running
    /// against a model the reader has just said they do not want.
    @Test func removeDuringDownloadCancelsIt() async throws {
        let (store, downloader, paths) = try make(release: try makeArchive().release)
        await store.start()
        store.download()
        downloader.progress(0.5)
        store.remove()
        #expect(downloader.cancels == 1)
        #expect(store.state == .absent)
        #expect(!store.isInstalledNow)
        #expect(!FileManager.default.fileExists(atPath: paths.resumeData.path))
        #expect(!FileManager.default.fileExists(atPath: paths.archive.path))
    }

    /// The next launch finds what the last one installed.
    @Test func startFindsAnInstalledVersion() async throws {
        let (data, release) = try makeArchive()
        let (store, downloader, paths) = try make(release: release)
        await store.start()
        store.download()
        try downloader.finish(with: data)
        await install(store)
        let again = KokoroStore(paths: paths, release: release, downloader: FakeDownloader())
        await again.start()
        #expect(again.state == .installed(version: "1", bytes: 1024 + 22))
        #expect(again.isInstalledNow)
    }

    /// Three leftovers with no marker between them: the pinned version's folder with its
    /// marker taken away, an unmarked older folder with its cache, and a leftover
    /// extraction folder. None of them is a model anyone can play, so all three are swept.
    @Test func startSweepsWhatShouldNotBeThere() async throws {
        let (data, release) = try makeArchive()
        let (store, downloader, paths) = try make(release: release)
        await store.start()
        store.download()
        try downloader.finish(with: data)
        await install(store)
        let fm = FileManager.default
        try fm.createDirectory(at: paths.modelDirectory(version: "0"), withIntermediateDirectories: true)
        try fm.createDirectory(at: paths.compiledCache(version: "0"), withIntermediateDirectories: true)
        try fm.createDirectory(at: paths.installing, withIntermediateDirectories: true)
        let unmarked = paths.modelDirectory(version: "1")
        try fm.removeItem(at: paths.marker(version: "1"))

        let again = KokoroStore(paths: paths, release: release, downloader: FakeDownloader())
        await again.start()

        #expect(again.state == .absent)
        #expect(!fm.fileExists(atPath: unmarked.path))
        #expect(!fm.fileExists(atPath: paths.modelDirectory(version: "0").path))
        #expect(!fm.fileExists(atPath: paths.compiledCache(version: "0").path))
        #expect(!fm.fileExists(atPath: paths.installing.path))
    }

    /// Last release's model is a working voice until its replacement has landed, so the
    /// sweep leaves a marked older version alone and takes it only once the pinned
    /// version is installed. It is never served in the meantime, just not deleted early.
    @Test func anOlderVersionStaysUntilTheNewOneIsInstalled() async throws {
        let (data, release) = try makeArchive()
        let (store, downloader, paths) = try make(release: release)
        let fm = FileManager.default
        try fm.createDirectory(at: paths.modelDirectory(version: "0"), withIntermediateDirectories: true)
        try Data().write(to: paths.marker(version: "0"))

        await store.start()
        #expect(store.state == .absent)
        #expect(fm.fileExists(atPath: paths.modelDirectory(version: "0").path))

        store.download()
        try downloader.finish(with: data)
        await install(store)

        let again = KokoroStore(paths: paths, release: release, downloader: FakeDownloader())
        await again.start()
        #expect(again.state == .installed(version: "1", bytes: 1024 + 22))
        #expect(!fm.fileExists(atPath: paths.modelDirectory(version: "0").path))
    }

    /// A crash between the download finishing and the marker leaves the archive behind.
    /// The next launch finishes that install rather than fetching 159 MB again.
    @Test func startInstallsAnArchiveLeftByACrash() async throws {
        let (data, release) = try makeArchive()
        let (store, _, paths) = try make(release: release)
        let fm = FileManager.default
        try fm.createDirectory(at: paths.support, withIntermediateDirectories: true)
        try data.write(to: paths.archive)

        await store.start()
        await install(store)
        #expect(store.state == .installed(version: "1", bytes: 1024 + 22))
        #expect(store.isInstalledNow)
        #expect(fm.fileExists(atPath: paths.marker(version: "1").path))
        #expect(!fm.fileExists(atPath: paths.archive.path))
    }

    /// The leftover is checked before it is trusted, so a half-written one is reported
    /// and deleted rather than unpacked.
    @Test func startDeletesAnArchiveThatDoesNotMatch() async throws {
        let (data, release) = try makeArchive()
        let (store, _, paths) = try make(release: release)
        let fm = FileManager.default
        try fm.createDirectory(at: paths.support, withIntermediateDirectories: true)
        var wrong = data
        wrong[wrong.count - 1] ^= 0xFF
        try wrong.write(to: paths.archive)

        await store.start()
        await install(store)
        #expect(store.state == .failed(KokoroStore.mismatchMessage))
        #expect(!store.isInstalledNow)
        #expect(!fm.fileExists(atPath: paths.archive.path))
        #expect(!fm.fileExists(atPath: paths.modelDirectory(version: "1").path))
    }

    /// A download the last launch left running is picked up, not restarted.
    @Test func startReattachesToARunningDownload() async throws {
        let (store, _, paths) = try make(release: try makeArchive().release)
        _ = store
        let downloader = FakeDownloader()
        downloader.running = true
        let again = KokoroStore(paths: paths, release: try makeArchive().release, downloader: downloader)
        await again.start()
        #expect(again.state == .downloading(0))
        #expect(downloader.requests.isEmpty)
        downloader.progress(0.7)
        #expect(again.state == .downloading(0.7))
    }

    /// Resume data from an app that quit mid-download is resumed at the next launch.
    @Test func startResumesFromResumeData() async throws {
        let (store, downloader, paths) = try make(release: try makeArchive().release)
        await store.start()
        store.download()
        downloader.fail(.offline, resumeData: Data("partial".utf8))
        let fresh = FakeDownloader()
        let again = KokoroStore(paths: paths, release: try makeArchive().release, downloader: fresh)
        await again.start()
        #expect(again.state == .downloading(0))
        #expect(fresh.requests.last?.resumeData == Data("partial".utf8))
    }
}
