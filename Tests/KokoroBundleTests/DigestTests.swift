import CryptoKit
import Foundation
import Testing

@testable import KokoroBundle

@Suite struct DigestTests {
    func scratch() throws -> URL {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        return url
    }

    func hex(_ digest: SHA256.Digest) -> String { digest.map { String(format: "%02x", $0) }.joined() }

    /// The tree digest is a hash over a list of per-file hashes, not over the bytes: the
    /// SDK feeds path, size and file hash, each followed by a zero byte, in path order.
    @Test func packageDigestIsTheSDKFormula() throws {
        let root = try scratch()
        let package = root.appendingPathComponent("kokoro_duration_t128.mlpackage")
        let payload = package.appendingPathComponent("Data/com.apple.CoreML")
        try FileManager.default.createDirectory(at: payload, withIntermediateDirectories: true)
        let data = Data("duration-128".utf8)
        try data.write(to: payload.appendingPathComponent("model.mlmodel"))

        let d = try Digest.package(at: package, path: "coreml/kokoro_duration_t128.mlpackage")

        let fileHash = hex(SHA256.hash(data: data))
        var hasher = SHA256()
        hasher.update(data: Data("Data/com.apple.CoreML/model.mlmodel".utf8))
        hasher.update(data: Data([0]))
        hasher.update(data: Data(String(data.count).utf8))
        hasher.update(data: Data([0]))
        hasher.update(data: Data(fileHash.utf8))
        hasher.update(data: Data([0]))
        #expect(d.treeSHA256 == hex(hasher.finalize()))
        #expect(d.path == "coreml/kokoro_duration_t128.mlpackage")
        #expect(d.fileCount == 1)
        #expect(d.bytes == data.count)
        #expect(
            d.files == [
                FileDigest(path: "Data/com.apple.CoreML/model.mlmodel", bytes: data.count, sha256: fileHash)
            ])
    }

    /// Files are taken in relative-path order however the file system lists them, and
    /// directories contribute nothing of their own.
    @Test func filesAreOrderedByRelativePath() throws {
        let root = try scratch()
        let package = root.appendingPathComponent("p.mlpackage")
        try FileManager.default.createDirectory(
            at: package.appendingPathComponent("Data/weights"), withIntermediateDirectories: true)
        try Data("z".utf8).write(to: package.appendingPathComponent("Manifest.json"))
        try Data("a".utf8).write(to: package.appendingPathComponent("Data/weights/weight.bin"))
        try Data("m".utf8).write(to: package.appendingPathComponent("Data/model.mlmodel"))

        let d = try Digest.package(at: package, path: "coreml/p.mlpackage")

        #expect(d.files.map(\.path) == ["Data/model.mlmodel", "Data/weights/weight.bin", "Manifest.json"])
        #expect(d.fileCount == 3)
        #expect(d.bytes == 3)
    }

    /// A symlink inside a package is refused, as the SDK refuses it at load.
    @Test func symlinksAreRefused() throws {
        let root = try scratch()
        let package = root.appendingPathComponent("p.mlpackage")
        try FileManager.default.createDirectory(at: package, withIntermediateDirectories: true)
        try Data("m".utf8).write(to: package.appendingPathComponent("model.mlmodel"))
        try FileManager.default.createSymbolicLink(
            at: package.appendingPathComponent("link"),
            withDestinationURL: package.appendingPathComponent("model.mlmodel"))

        #expect(throws: DigestError.self) { try Digest.package(at: package, path: "coreml/p.mlpackage") }
    }

    /// A file digest is the streamed SHA-256 of the bytes and the byte count.
    @Test func fileDigestStreamsTheWholeFile() throws {
        let root = try scratch()
        let url = root.appendingPathComponent("v.bin")
        let data = Data((0..<3_000_000).map { UInt8(truncatingIfNeeded: $0) })
        try data.write(to: url)

        let d = try Digest.file(at: url, path: "voices/v.bin")

        #expect(
            d == FileDigest(path: "voices/v.bin", bytes: data.count, sha256: hex(SHA256.hash(data: data))))
    }
}
