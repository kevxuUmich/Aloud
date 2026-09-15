import CryptoKit
import Foundation
import Testing

@testable import KokoroBundle

@Suite struct AppleArchiveFileTests {
    func scratch() throws -> URL {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        return url
    }

    /// A tree with a nested package, a voice and a manifest, as a bundle has.
    func makeTree(in root: URL, stamp: Date) throws {
        let fm = FileManager.default
        try fm.createDirectory(
            at: root.appendingPathComponent("coreml/p.mlpackage/Data"), withIntermediateDirectories: true)
        try fm.createDirectory(at: root.appendingPathComponent("voices"), withIntermediateDirectories: true)
        try Data((0..<200_000).map { UInt8(truncatingIfNeeded: $0 % 251) })
            .write(to: root.appendingPathComponent("coreml/p.mlpackage/Data/weight.bin"))
        try Data(count: 1024).write(to: root.appendingPathComponent("voices/af_bella.bin"))
        try Data("{}\n".utf8).write(to: root.appendingPathComponent("KokoroRuntimeManifest.json"))
        try BundleBuilder.normalisePermissions(under: root)
        for path in ["KokoroRuntimeManifest.json", "voices/af_bella.bin"] {
            try fm.setAttributes(
                [.modificationDate: stamp], ofItemAtPath: root.appendingPathComponent(path).path)
        }
    }

    @Test func aTreeSurvivesTheRoundTrip() throws {
        let src = try scratch()
        try makeTree(in: src, stamp: Date())
        let archive = try scratch().appendingPathComponent("t.aar")
        let dst = try scratch().appendingPathComponent("out")

        try AppleArchiveFile.compress(directory: src, to: archive)
        try AppleArchiveFile.extract(archive: archive, into: dst)

        for path in [
            "coreml/p.mlpackage/Data/weight.bin", "voices/af_bella.bin", "KokoroRuntimeManifest.json",
        ] {
            #expect(
                try Data(contentsOf: dst.appendingPathComponent(path))
                    == Data(contentsOf: src.appendingPathComponent(path)),
                "\(path)")
        }
        #expect(
            try FileManager.default.attributesOfItem(
                atPath: dst.appendingPathComponent("voices/af_bella.bin").path)[
                    .posixPermissions] as? Int == 0o644)
    }

    /// The same files archived on two days, or two machines, are the same bytes: the
    /// archive carries no times and no owners.
    @Test func twoArchivesOfTheSameTreeAreIdentical() throws {
        let a = try scratch()
        let b = try scratch()
        try makeTree(in: a, stamp: Date(timeIntervalSince1970: 0))
        try makeTree(in: b, stamp: Date())
        let archiveA = try scratch().appendingPathComponent("a.aar")
        let archiveB = try scratch().appendingPathComponent("b.aar")

        try AppleArchiveFile.compress(directory: a, to: archiveA)
        try AppleArchiveFile.compress(directory: b, to: archiveB)

        #expect(try Data(contentsOf: archiveA) == Data(contentsOf: archiveB))
    }

    @Test func aFileThatIsNotAnArchiveIsRefused() throws {
        let notArchive = try scratch().appendingPathComponent("x.aar")
        try Data("not an archive".utf8).write(to: notArchive)
        let dst = try scratch().appendingPathComponent("out")
        #expect(throws: (any Error).self) { try AppleArchiveFile.extract(archive: notArchive, into: dst) }
    }
}
