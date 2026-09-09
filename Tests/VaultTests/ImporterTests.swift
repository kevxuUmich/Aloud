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
        let out = try Importer.importFiles(
            [src.appendingPathComponent("a.md"), src.appendingPathComponent("b.png")], into: dst)
        #expect(out.map(\.lastPathComponent) == ["a.md"])
        #expect(try String(contentsOf: dst.appendingPathComponent("a.md"), encoding: .utf8) == "a")
    }
    @Test func collisionsCount() throws {
        let src = try temp(), dst = try temp()
        try "x".write(to: src.appendingPathComponent("n.txt"), atomically: true, encoding: .utf8)
        try "old".write(to: dst.appendingPathComponent("n.txt"), atomically: true, encoding: .utf8)
        let out = try Importer.importFiles([src.appendingPathComponent("n.txt")], into: dst)
        #expect(out.map(\.lastPathComponent) == ["n 2.txt"])
        #expect(try String(contentsOf: dst.appendingPathComponent("n.txt"), encoding: .utf8) == "old")
    }
}
