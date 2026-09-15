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

    /// The four buckets share their weights byte for byte, so the weight file is
    /// downloaded once and the copies after it come from the one already on disk.
    @Test func anIdenticalFileIsReusedRatherThanFetchedAgain() async throws {
        let inputs = try scratch()
        let bytes = Data((0..<4096).map { UInt8(truncatingIfNeeded: $0 % 251) })
        let (first, _) = try pinned(bytes, path: "coreml/a.mlpackage/weights/weight.bin")
        let (second, _) = try pinned(bytes, path: "coreml/b.mlpackage/weights/weight.bin")
        let server = Server()
        let fetcher = Fetcher(inputs: inputs) { try server.download($0) }

        try await fetcher.fetch([first, second]) { _ in }

        #expect(server.calls == 1)
        #expect(try fetcher.isPresent(second))
        #expect(try Data(contentsOf: inputs.appendingPathComponent(second.path)) == bytes)
    }

    /// The reuse looks at what is already in the inputs folder, not only at what this
    /// run downloaded, so a later run that adds a bucket beside one already fetched
    /// does not fetch the shared weights a second time.
    @Test func aFileAlreadyOnDiskIsReusedByALaterIdenticalInput() async throws {
        let inputs = try scratch()
        let bytes = Data((0..<4096).map { UInt8(truncatingIfNeeded: $0 % 241) })
        let (first, _) = try pinned(bytes, path: "coreml/a.mlpackage/weights/weight.bin")
        let (second, _) = try pinned(bytes, path: "coreml/b.mlpackage/weights/weight.bin")
        let server = Server()
        let fetcher = Fetcher(inputs: inputs) { try server.download($0) }

        try await fetcher.fetch([first]) { _ in }
        try await fetcher.fetch([second, first]) { _ in }

        #expect(server.calls == 1)
        #expect(try fetcher.isPresent(second))
    }

    /// The pinned list is what the bundle is: thirteen packages of three files, seven
    /// voices, two assets, every path inside the inputs folder.
    /// 13 * 3 + 7 + 2 = 48.
    @Test func thePinnedListIsComplete() {
        let paths = KokoroInputs.all.map(\.path)
        #expect(paths.count == 48)
        #expect(Set(paths).count == 48)
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
            Set(KokoroInputs.treeDigests.keys)
                == Set(KokoroInputs.packages.map { "coreml/\($0).mlpackage" }))
    }

    /// Every URL is built from its base and the pinned path: the first entry from the
    /// Hugging Face base, the last from the SDK's raw GitHub base.
    @Test func theURLsAreBuiltFromTheBases() {
        #expect(
            KokoroInputs.all[0].url.absoluteString
                == "https://huggingface.co/mattmireles/kokoro-coreml/resolve/9b6c8dbcf1209eedb554ca2fe98e947948061638/coreml/kokoro_duration_t128.mlpackage/Manifest.json"
        )
        #expect(
            KokoroInputs.all.last!.url.absoluteString
                == "https://raw.githubusercontent.com/kevinxu-cmd/kokoro-coreml/2932a26444b8deba2a6be6c0aa45c0424efaefe1/swift-tts/Sources/KokoroTTS/Resources/KokoroRuntime/hnsf_weights.json"
        )
    }
}
