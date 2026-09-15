import CryptoKit
import Foundation
import KokoroBundle
import Synchronization

public enum KokoroStoreState: Sendable, Equatable {
    case absent
    case downloading(Double)
    case installing
    case installed(version: String, bytes: Int64)
    case failed(String)
}

public enum KokoroDownloadFailure: Error, Sendable, Equatable {
    case offline
    case http(Int)
    case other(String)
}

/// What a downloader tells the store, on the main actor.
@MainActor
public protocol KokoroDownloadDelegate: AnyObject {
    func downloadProgressed(_ fraction: Double)
    /// The file is at the destination the download was asked for.
    func downloadFinished()
    func downloadFailed(_ failure: KokoroDownloadFailure, resumeData: Data?)
}

/// Downloads one file. The background session is the real one; tests drive a fake.
public protocol KokoroDownloading: AnyObject, Sendable {
    @MainActor func download(
        _ url: URL, to destination: URL, resumeData: Data?, delegate: any KokoroDownloadDelegate)
    /// Picks up a download a previous launch left running. True when there is one.
    @MainActor func reattach(to destination: URL, delegate: any KokoroDownloadDelegate) async -> Bool
    @MainActor func cancel()
}

/// The model's life on disk: absent, arriving, being checked and unpacked, installed,
/// or failed with a sentence. The one writer of the model folders.
@Observable @MainActor
public final class KokoroStore {
    public static let mismatchMessage = "The download did not match what Aloud expected."
    public static let offlineMessage = "No internet connection."
    public static let diskFullMessage = "Not enough disk space."
    public static let unpackMessage = "The model could not be unpacked."

    public private(set) var state: KokoroStoreState = .absent {
        didSet {
            installedFlag.withLock { $0 = isInstalled }
        }
    }
    /// Called once an install completes, so a pick made before the download can take.
    public var onInstalled: (@MainActor () -> Void)?
    /// True when this launch found a model from a version this build cannot load and
    /// swept it. The reader had those voices until a moment ago, so this is not the same
    /// as never having downloaded: the app model turns it into the download they already
    /// consented to when they picked the voice. Cleared when that download installs, and
    /// when the reader answers it by removing the model instead.
    public private(set) var needsUpdate = false

    public let paths: KokoroPaths
    public let release: KokoroReleaseInfo
    private let downloader: any KokoroDownloading
    private let extract: @Sendable (URL, URL) throws -> Void
    /// What the volume has left for something the reader asked for. Injected so a test
    /// can say "full" without filling a disk.
    private let availableBytes: @Sendable (URL) -> Int64
    /// The provider's `voices` is read nonisolated, so it reads this rather than `state`.
    private let installedFlag = Mutex(false)
    /// Bumped on cancel and remove, so a callback from a download that is no longer
    /// wanted changes nothing.
    private var generation = 0
    /// The checksum and the extraction, off the main actor. Internal so a test can wait.
    private(set) var installTask: Task<Void, Never>?

    public init(
        paths: KokoroPaths, release: KokoroReleaseInfo, downloader: any KokoroDownloading,
        extract: @escaping @Sendable (URL, URL) throws -> Void = AppleArchiveFile.extract,
        availableBytes: @escaping @Sendable (URL) -> Int64 = KokoroStore.volumeAvailableBytes
    ) {
        self.paths = paths
        self.release = release
        self.downloader = downloader
        self.extract = extract
        self.availableBytes = availableBytes
    }

    /// What the volume holding `url` would give up for a download the reader asked for.
    /// A volume that will not say is treated as roomy rather than blocking the install.
    public static let volumeAvailableBytes: @Sendable (URL) -> Int64 = { url in
        let keys: Set<URLResourceKey> = [.volumeAvailableCapacityForImportantUsageKey]
        guard
            let capacity = (try? url.resourceValues(forKeys: keys))?
                .volumeAvailableCapacityForImportantUsage
        else { return .max }
        return capacity
    }

    public nonisolated var isInstalledNow: Bool { installedFlag.withLock { $0 } }

    private var isInstalled: Bool {
        if case .installed = state { return true }
        return false
    }

    public var installedRoot: URL? { isInstalled ? paths.modelDirectory(version: release.version) : nil }
    public var compiledCache: URL { paths.compiledCache(version: release.version) }

    /// The launch sweep: leftovers go, an installed version is found, and a download
    /// left running or interrupted is picked up where it was.
    public func start() async {
        let fm = FileManager.default
        try? fm.createDirectory(at: paths.support, withIntermediateDirectories: true)
        try? fm.removeItem(at: paths.installing)
        let versions =
            (try? fm.contentsOfDirectory(at: paths.support, includingPropertiesForKeys: [.isDirectoryKey]))
            ?? []
        // Nothing but the pinned version can ever be played: `installedRoot` names that
        // one folder and the SDK is loaded from it, so a model left by an older build is
        // dead weight the reader has no way to reclaim. It goes at the launch that finds
        // it, and a marked one going while the pinned one is absent is what "an update is
        // needed" means. A folder with no marker is a crash mid-install and says nothing.
        let pinnedIsInstalled = fm.fileExists(atPath: paths.marker(version: release.version).path)
        for folder in versions
        where (try? folder.resourceValues(forKeys: [.isDirectoryKey]).isDirectory) == true {
            let version = folder.lastPathComponent
            let marked = fm.fileExists(atPath: paths.marker(version: version).path)
            if version == release.version && marked { continue }
            if marked && !pinnedIsInstalled { needsUpdate = true }
            try? fm.removeItem(at: folder)
            try? fm.removeItem(at: paths.compiledCache(version: version))
        }
        if pinnedIsInstalled {
            state = .installed(
                version: release.version, bytes: Self.size(of: paths.modelDirectory(version: release.version))
            )
            return
        }
        // Said before the await, not after it. Creating the session is what makes the
        // system replay a download that finished while the app was quit, and that replay
        // arrives inside `reattach`: a store still reading `.absent` would drop it on
        // `downloadFinished`'s guard and fetch the 159 MB again.
        state = .downloading(0)
        if await downloader.reattach(to: paths.archive, delegate: self) { return }
        // Nothing was running. Unless the replay above already took it somewhere, this
        // launch is back where it started and the branches below are the real answer.
        guard case .downloading = state else { return }
        state = .absent
        if fm.fileExists(atPath: paths.resumeData.path) {
            download()
            return
        }
        // A crash between the download finishing and the marker: the bytes are still
        // here, and install() checks them before trusting them, so a corrupt leftover
        // fails into .failed and is deleted rather than being served.
        if fm.fileExists(atPath: paths.archive.path) { install() }
    }

    public func download() {
        guard !isInstalled else { return }
        if case .downloading = state { return }
        if case .installing = state { return }
        let resume = try? Data(contentsOf: paths.resumeData)
        try? FileManager.default.createDirectory(at: paths.support, withIntermediateDirectories: true)
        // Said before a byte is fetched. install() asks again, for a volume that filled
        // up while the download was running.
        guard Self.hasRoom(for: release, at: paths.support, availableBytes: availableBytes) else {
            state = .failed(Self.diskFullMessage)
            return
        }
        try? FileManager.default.removeItem(at: paths.archive)
        state = .downloading(0)
        downloader.download(release.url, to: paths.archive, resumeData: resume, delegate: self)
    }

    public func cancel() {
        guard case .downloading = state else { return }
        generation += 1
        downloader.cancel()
        try? FileManager.default.removeItem(at: paths.resumeData)
        try? FileManager.default.removeItem(at: paths.archive)
        state = .absent
    }

    public func remove() {
        generation += 1
        // The reader was told an update was needed and has answered by removing the
        // model instead. That is an answer, so the flag stops asking.
        needsUpdate = false
        installTask?.cancel()
        // A remove during a download is still a remove: the transfer stops and its bytes go.
        if case .downloading = state {
            downloader.cancel()
            try? FileManager.default.removeItem(at: paths.resumeData)
            try? FileManager.default.removeItem(at: paths.archive)
        }
        try? FileManager.default.removeItem(at: paths.modelDirectory(version: release.version))
        try? FileManager.default.removeItem(at: paths.compiledCache(version: release.version))
        state = .absent
    }

    /// Checksum, extract, move into place, mark. Off the main actor: the archive is
    /// 159 MB and the reader's window must not freeze for it.
    private func install() {
        state = .installing
        let gen = generation
        let paths = paths
        let release = release
        let extract = extract
        let availableBytes = availableBytes
        installTask = Task.detached(priority: .userInitiated) {
            let outcome: Result<Int64, Error> = Result {
                try Task.checkCancellation()
                guard Self.hasRoom(for: release, at: paths.support, availableBytes: availableBytes) else {
                    throw InstallError.diskFull
                }
                guard try Self.sha256(of: paths.archive) == release.sha256 else {
                    throw InstallError.mismatch
                }
                let fm = FileManager.default
                try? fm.removeItem(at: paths.installing)
                try extract(paths.archive, paths.installing)
                // A remove during the extraction stops the install here, before anything
                // is moved into place. The stale generation below swallows the error.
                try Task.checkCancellation()
                var destination = paths.modelDirectory(version: release.version)
                try? fm.removeItem(at: destination)
                try fm.moveItem(at: paths.installing, to: destination)
                // Several hundred megabytes reproducible from a pinned URL and a pinned
                // hash. A backup should no more carry the tree than the cache below.
                var tree = URLResourceValues()
                tree.isExcludedFromBackup = true
                try? destination.setResourceValues(tree)
                try Data().write(to: paths.marker(version: release.version))
                try fm.createDirectory(
                    at: paths.compiledCache(version: release.version), withIntermediateDirectories: true)
                var cache = paths.compiledCache(version: release.version)
                var values = URLResourceValues()
                values.isExcludedFromBackup = true
                try? cache.setResourceValues(values)
                try? fm.removeItem(at: paths.archive)
                try? fm.removeItem(at: paths.resumeData)
                return Self.size(of: destination)
            }
            await self.finishInstall(outcome, generation: gen)
        }
    }

    /// Internal rather than private so the suite can hand the store a completion from an
    /// install two removes ago without racing a real 159 MB extraction to do it.
    func finishInstall(_ outcome: Result<Int64, Error>, generation gen: Int) {
        // An install that outran a remove: its outcome is discarded, and so is whatever
        // it managed to put in place after the remove swept the folders. Unless a newer
        // install is already running, in which case the folders and the handle are that
        // one's and this stale completion must touch neither.
        guard gen == generation else {
            guard installTask == nil else { return }
            let fm = FileManager.default
            try? fm.removeItem(at: paths.modelDirectory(version: release.version))
            try? fm.removeItem(at: paths.compiledCache(version: release.version))
            try? fm.removeItem(at: paths.installing)
            return
        }
        installTask = nil
        switch outcome {
        case .success(let bytes):
            state = .installed(version: release.version, bytes: bytes)
            // The update the sweep asked for has landed, so the flag has done its work.
            // It is read once per launch today, but it is a flag with a reason to be
            // false again and nothing should have to know that it is read only once.
            needsUpdate = false
            onInstalled?()
        case .failure(let error):
            try? FileManager.default.removeItem(at: paths.archive)
            // Resume data points at bytes that did not check out, so a retry starts over
            // rather than resuming the same bad download.
            try? FileManager.default.removeItem(at: paths.resumeData)
            try? FileManager.default.removeItem(at: paths.installing)
            try? FileManager.default.removeItem(at: paths.modelDirectory(version: release.version))
            state = .failed(Self.message(for: error))
        }
    }

    enum InstallError: Error { case mismatch, diskFull }

    /// The archive, the tree it unpacks to and the compiled cache, roughly. One place,
    /// so the check before the download and the check before the extraction agree.
    nonisolated static func hasRoom(
        for release: KokoroReleaseInfo, at support: URL, availableBytes: (URL) -> Int64
    ) -> Bool {
        availableBytes(support) >= 3 * release.bytes
    }

    static func message(for error: Error) -> String {
        if let install = error as? InstallError {
            switch install {
            case .mismatch: return mismatchMessage
            case .diskFull: return diskFullMessage
            }
        }
        if error is ArchiveError { return unpackMessage }
        let ns = error as NSError
        if ns.domain == NSCocoaErrorDomain && ns.code == NSFileWriteOutOfSpaceError { return diskFullMessage }
        if ns.domain == NSPOSIXErrorDomain && ns.code == Int(ENOSPC) { return diskFullMessage }
        return error.localizedDescription
    }

    nonisolated static func sha256(of url: URL) throws -> String {
        let handle = try FileHandle(forReadingFrom: url)
        defer { try? handle.close() }
        var hasher = SHA256()
        while true {
            let chunk = try handle.read(upToCount: 1 << 20) ?? Data()
            if chunk.isEmpty { break }
            hasher.update(data: chunk)
        }
        return hasher.finalize().map { String(format: "%02x", $0) }.joined()
    }

    /// The regular files under a folder, in bytes: what Settings shows beside Remove.
    ///
    /// A file reached by more than one name counts once. The bundle's four acoustic
    /// buckets share one copy of each weight file, so counting every link would say
    /// "558 MB" for a tree that takes 169 MB of disk, beside a badge that says 159 MB.
    nonisolated static func size(of folder: URL) -> Int64 {
        let keys: Set<URLResourceKey> = [.fileSizeKey, .isRegularFileKey, .fileIdentifierKey]
        guard
            let e = FileManager.default.enumerator(at: folder, includingPropertiesForKeys: Array(keys))
        else {
            return 0
        }
        var total: Int64 = 0
        var counted: Set<UInt64> = []
        for case let url as URL in e {
            guard let v = try? url.resourceValues(forKeys: keys), v.isRegularFile == true else { continue }
            if let identifier = v.fileIdentifier, !counted.insert(identifier).inserted { continue }
            total += Int64(v.fileSize ?? 0)
        }
        return total
    }
}

extension KokoroStore: KokoroDownloadDelegate {
    public func downloadProgressed(_ fraction: Double) {
        guard case .downloading = state else { return }
        state = .downloading(fraction)
    }

    public func downloadFinished() {
        guard case .downloading = state else { return }
        install()
    }

    public func downloadFailed(_ failure: KokoroDownloadFailure, resumeData: Data?) {
        guard case .downloading = state else { return }
        if let resumeData {
            try? resumeData.write(to: paths.resumeData)
        } else {
            try? FileManager.default.removeItem(at: paths.resumeData)
        }
        switch failure {
        case .offline: state = .failed(Self.offlineMessage)
        case .http(let code): state = .failed("The server answered \(code).")
        case .other(let text): state = .failed(text)
        }
    }
}
