import Foundation
import Testing

@testable import Vault

@Suite struct SearchTests {
    func doc(_ name: String, _ body: String, in dir: URL) throws -> Document {
        let url = dir.appendingPathComponent(name)
        try body.write(to: url, atomically: true, encoding: .utf8)
        return Document(
            url: url, title: Title.from(text: body, fallback: name), preview: body, modified: .now,
            bytes: body.utf8.count, type: DocumentType(url: url)!)
    }
    @Test func matchesTitleAndBody() async throws {
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        let a = try doc("a.md", "# Fast Year\n\nnothing here", in: dir)
        let b = try doc("b.txt", "plain start\n\nthe word hamming appears", in: dir)
        let hits = await Search.matches("hamming", in: [a, b])
        #expect(hits == [b.id])
        let byTitle = await Search.matches("fast", in: [a, b])
        #expect(byTitle == [a.id])
        let diacritic = await Search.matches("HAMMÍNG", in: [a, b])
        #expect(diacritic == [b.id])
    }
    @Test func emptyQueryMatchesAll() async throws {
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        let a = try doc("a.md", "x", in: dir)
        #expect(await Search.matches("  ", in: [a]) == [a.id])
    }
}
