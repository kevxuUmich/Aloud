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
    @Test func pdfsMatchOnTitleOnly() async throws {
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        // Both files hold the word; only the one whose title holds it is a hit.
        let titled = dir.appendingPathComponent("t.pdf")
        try "hamming inside".write(to: titled, atomically: true, encoding: .utf8)
        let a = Document(
            url: titled, title: "The Hamming Talk", preview: "", modified: .now, bytes: 0, type: .pdf)
        let bodied = dir.appendingPathComponent("b.pdf")
        try "hamming inside".write(to: bodied, atomically: true, encoding: .utf8)
        let b = Document(url: bodied, title: "Slides", preview: "", modified: .now, bytes: 0, type: .pdf)
        #expect(await Search.matches("hamming", in: [a, b]) == [a.id])
    }
    @Test func aCancelledSearchStopsReading() async throws {
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        // The word is off the first line, so every hit costs a file read.
        let docs = try (0..<200).map { try doc("f\($0).md", "# note \($0)\n\nneedle", in: dir) }
        #expect(await Search.matches("needle", in: docs).count == docs.count)
        let task = Task { () -> Set<String> in
            // Start the search only once the cancellation has landed, so the loop's
            // first check is the one under test rather than a race with it.
            while !Task.isCancelled { await Task.yield() }
            return await Search.matches("needle", in: docs)
        }
        task.cancel()
        #expect(await task.value.isEmpty)
    }
    @Test func emptyQueryMatchesAll() async throws {
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        let a = try doc("a.md", "x", in: dir)
        #expect(await Search.matches("  ", in: [a]) == [a.id])
    }
}
