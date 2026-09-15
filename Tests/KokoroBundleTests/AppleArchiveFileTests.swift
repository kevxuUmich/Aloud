import Foundation
import Testing

@testable import KokoroBundle

@Suite struct AppleArchiveFileTests {
    func scratch() throws -> URL {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        return url
    }

    /// A tree with a nested package, a voice and a manifest, as a bundle has, and a
    /// second package that is a hard link to the first's weight, as the four acoustic
    /// buckets are. The link is here rather than in its own fixture so the determinism
    /// test covers cluster-id assignment, which is the one thing deduplication could
    /// make depend on the order the tree was laid down in.
    func makeTree(in root: URL, stamp: Date) throws {
        let fm = FileManager.default
        try fm.createDirectory(
            at: root.appendingPathComponent("coreml/p.mlpackage/Data"), withIntermediateDirectories: true)
        try fm.createDirectory(
            at: root.appendingPathComponent("coreml/q.mlpackage/Data"), withIntermediateDirectories: true)
        try fm.createDirectory(at: root.appendingPathComponent("voices"), withIntermediateDirectories: true)
        try Data((0..<200_000).map { UInt8(truncatingIfNeeded: $0 % 251) })
            .write(to: root.appendingPathComponent("coreml/p.mlpackage/Data/weight.bin"))
        try fm.linkItem(
            at: root.appendingPathComponent("coreml/p.mlpackage/Data/weight.bin"),
            to: root.appendingPathComponent("coreml/q.mlpackage/Data/weight.bin"))
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
            "coreml/p.mlpackage/Data/weight.bin", "coreml/q.mlpackage/Data/weight.bin",
            "voices/af_bella.bin", "KokoroRuntimeManifest.json",
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

    /// Bytes an LZFSE block cannot shrink, so a size assertion below is about what the
    /// archive stored and not about what compressed away.
    func incompressible(_ count: Int, seed: UInt64) -> Data {
        var state = seed
        var bytes = Data(capacity: count)
        for _ in 0..<count {
            state = state &* 6_364_136_223_846_793_005 &+ 1_442_695_040_888_963_407
            bytes.append(UInt8(truncatingIfNeeded: state >> 33))
        }
        return bytes
    }

    /// The four buckets' weights are one inode in the built tree, so the archive must
    /// carry those bytes once and give the hard links back on extraction. Without this
    /// the bundle would grow by about 127 MB a bucket.
    @Test func duplicatedFilesAreStoredOnceAndExtractAsHardLinks() throws {
        let src = try scratch()
        let fm = FileManager.default
        let payload = incompressible(4_000_000, seed: 7)
        let first = src.appendingPathComponent("coreml/a.mlpackage/weight.bin")
        try fm.createDirectory(at: first.deletingLastPathComponent(), withIntermediateDirectories: true)
        try payload.write(to: first)
        for name in ["b", "c"] {
            let twin = src.appendingPathComponent("coreml/\(name).mlpackage/weight.bin")
            try fm.createDirectory(at: twin.deletingLastPathComponent(), withIntermediateDirectories: true)
            try fm.linkItem(at: first, to: twin)
        }
        try BundleBuilder.normalisePermissions(under: src)
        let archive = try scratch().appendingPathComponent("t.aar")
        let dst = try scratch().appendingPathComponent("out")

        try AppleArchiveFile.compress(directory: src, to: archive)
        try AppleArchiveFile.extract(archive: archive, into: dst)

        let size = try #require(try fm.attributesOfItem(atPath: archive.path)[.size] as? Int)
        #expect(size < payload.count * 3 / 2, "\(size)")
        var inodes: Set<Int> = []
        for name in ["a", "b", "c"] {
            let file = dst.appendingPathComponent("coreml/\(name).mlpackage/weight.bin")
            #expect(try Data(contentsOf: file) == payload, "\(name)")
            let attributes = try fm.attributesOfItem(atPath: file.path)
            #expect(attributes[.posixPermissions] as? Int == 0o644, "\(name)")
            inodes.insert(try #require(attributes[.systemFileNumber] as? Int))
        }
        #expect(inodes.count == 1, "\(inodes.count)")
    }

    @Test func aFileThatIsNotAnArchiveIsRefused() throws {
        let notArchive = try scratch().appendingPathComponent("x.aar")
        try Data("not an archive".utf8).write(to: notArchive)
        let dst = try scratch().appendingPathComponent("out")
        #expect(throws: (any Error).self) { try AppleArchiveFile.extract(archive: notArchive, into: dst) }
    }

    @Test func compressIntoAMissingFolderIsRefused() throws {
        let src = try scratch()
        try makeTree(in: src, stamp: Date())
        let missing = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
            .appendingPathComponent("nested").appendingPathComponent("t.aar")
        #expect(throws: ArchiveError.self) { try AppleArchiveFile.compress(directory: src, to: missing) }
    }
}
