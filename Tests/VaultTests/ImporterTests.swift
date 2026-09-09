import Foundation
import Testing

@testable import Vault

@Suite struct ImporterTests {
    func temp() throws -> URL {
        let u = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: u, withIntermediateDirectories: true)
        return u
    }
    @Test func copiesSupportedFilesAndSkipsOthers() throws {
        let src = try temp(), dst = try temp()
        try "a".write(to: src.appendingPathComponent("a.md"), atomically: true, encoding: .utf8)
        try "b".write(to: src.appendingPathComponent("b.png"), atomically: true, encoding: .utf8)
        let out = Importer.importFiles(
            [src.appendingPathComponent("a.md"), src.appendingPathComponent("b.png")], into: dst)
        #expect(out.added.map(\.lastPathComponent) == ["a.md"])
        #expect(out.failed.isEmpty)
        #expect(try String(contentsOf: dst.appendingPathComponent("a.md"), encoding: .utf8) == "a")
    }
    @Test func collisionsCount() throws {
        let src = try temp(), dst = try temp()
        try "x".write(to: src.appendingPathComponent("n.txt"), atomically: true, encoding: .utf8)
        try "old".write(to: dst.appendingPathComponent("n.txt"), atomically: true, encoding: .utf8)
        let out = Importer.importFiles([src.appendingPathComponent("n.txt")], into: dst)
        #expect(out.added.map(\.lastPathComponent) == ["n 2.txt"])
        #expect(out.failed.isEmpty)
        #expect(try String(contentsOf: dst.appendingPathComponent("n.txt"), encoding: .utf8) == "old")
    }
    /// One file that cannot be read must not cost the caller the rest of the drop.
    @Test func anUnreadableFileIsCollectedAndTheRestStillLand() throws {
        try #require(getuid() != 0, "root can read a mode 000 file, so this case cannot arise")
        let src = try temp(), dst = try temp()
        let bad = src.appendingPathComponent("bad.md")
        let good = src.appendingPathComponent("good.md")
        try "bad".write(to: bad, atomically: true, encoding: .utf8)
        try "good".write(to: good, atomically: true, encoding: .utf8)
        try FileManager.default.setAttributes([.posixPermissions: 0], ofItemAtPath: bad.path)
        defer { try? FileManager.default.setAttributes([.posixPermissions: 0o644], ofItemAtPath: bad.path) }
        let out = Importer.importFiles([bad, good], into: dst)
        #expect(out.added.map(\.lastPathComponent) == ["good.md"])
        #expect(out.failed.map(\.lastPathComponent) == ["bad.md"])
        #expect(try String(contentsOf: dst.appendingPathComponent("good.md"), encoding: .utf8) == "good")
    }
}
