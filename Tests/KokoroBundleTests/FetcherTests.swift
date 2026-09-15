import Foundation
import Testing

@testable import KokoroBundle

@Suite struct FetcherTests {
    func scratch() throws -> URL {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        return url
    }

    /// A pinned input whose "download" is a local file, so the fetcher can be driven
    /// without a network.
    func pinned(_ data: Data, path: String = "kokoro.js/voices/af_bella.bin", sha256: String? = nil) throws
        -> (
            PinnedInput, URL
        )
    {
        let served = try scratch().appendingPathComponent("served.bin")
        try data.write(to: served)
        let input = PinnedInput(
            path: path, url: served, bytes: data.count, sha256: sha256 ?? Digest.sha256(of: data))
        return (input, served)
    }

    /// Serves by copying, so a moved temp file never eats the source, and counts calls.
    final class Server: @unchecked Sendable {
        let lock = NSLock()
        var calls = 0
        func download(_ url: URL) throws -> URL {
            lock.withLock { calls += 1 }
            let tmp = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
            try FileManager.default.copyItem(at: url, to: tmp)
            return tmp
        }
    }

    @Test func aMissingInputIsFetchedAndVerified() async throws {
        let inputs = try scratch()
        let (input, _) = try pinned(Data(count: 1024))
        let server = Server()
        let fetcher = Fetcher(inputs: inputs) { try server.download($0) }

        try await fetcher.fetch([input]) { _ in }

        #expect(try fetcher.isPresent(input))
        #expect(try Data(contentsOf: inputs.appendingPathComponent(input.path)) == Data(count: 1024))
        #expect(server.calls == 1)
    }

    @Test func aPresentAndMatchingInputIsNotFetchedAgain() async throws {
        let inputs = try scratch()
        let (input, _) = try pinned(Data(count: 1024))
        let server = Server()
        let fetcher = Fetcher(inputs: inputs) { try server.download($0) }

        try await fetcher.fetch([input]) { _ in }
        try await fetcher.fetch([input]) { _ in }

        #expect(server.calls == 1)
    }

    /// A file on disk with the right size and the wrong bytes is fetched again, and one
    /// whose download does not match is thrown away and the run fails.
    @Test func aMismatchIsDiscarded() async throws {
        let inputs = try scratch()
        let (input, _) = try pinned(Data(count: 1024), sha256: String(repeating: "0", count: 64))
        let server = Server()
        let fetcher = Fetcher(inputs: inputs) { try server.download($0) }

        await #expect(throws: FetchError.mismatch("kokoro.js/voices/af_bella.bin")) {
            try await fetcher.fetch([input]) { _ in }
        }
        #expect(!FileManager.default.fileExists(atPath: inputs.appendingPathComponent(input.path).path))
    }

    @Test func aStaleFileWithTheRightSizeIsReplaced() async throws {
        let inputs = try scratch()
        var good = Data(count: 1024)
        good[0] = 1
        let (input, _) = try pinned(good)
        let stale = inputs.appendingPathComponent(input.path)
        try FileManager.default.createDirectory(
            at: stale.deletingLastPathComponent(), withIntermediateDirectories: true)
        try Data(count: 1024).write(to: stale)
        let server = Server()
        let fetcher = Fetcher(inputs: inputs) { try server.download($0) }

        #expect(try !fetcher.isPresent(input))
        try await fetcher.fetch([input]) { _ in }

        #expect(server.calls == 1)
        #expect(try Data(contentsOf: stale) == good)
    }

    /// The pinned list is what the bundle is: four packages of three files, seven
    /// voices, two assets, every path inside the inputs folder.
    @Test func thePinnedListIsComplete() {
        let paths = KokoroInputs.all.map(\.path)
        #expect(paths.count == 21)
        #expect(Set(paths).count == 21)
        for name in KokoroInputs.packages {
            for file in [
                "Manifest.json", "Data/com.apple.CoreML/model.mlmodel",
                "Data/com.apple.CoreML/weights/weight.bin",
            ] {
                #expect(paths.contains("coreml/\(name).mlpackage/\(file)"), "\(name)/\(file)")
            }
        }
        for voice in KokoroInputs.voices {
            #expect(paths.contains("kokoro.js/voices/\(voice).bin"), "\(voice)")
        }
        #expect(paths.contains("runtime/kokoro-vocab.json"))
        #expect(paths.contains("runtime/hnsf_weights.json"))
        #expect(
            KokoroInputs.all.allSatisfy {
                $0.sha256.count == 64 && !$0.path.hasPrefix("/") && !$0.path.contains("..")
            })
        #expect(
            KokoroInputs.all.filter { $0.path.hasPrefix("kokoro.js/") }.allSatisfy { $0.bytes == 522_240 })
        #expect(
            Set(KokoroInputs.expectedTreeDigests.keys)
                == Set(KokoroInputs.packages.map { "coreml/\($0).mlpackage" }))
    }
}
