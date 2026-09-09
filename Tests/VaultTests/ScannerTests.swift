import Foundation
import Testing

@testable import Vault

@Suite struct ScannerTests {
    func makeTree() throws -> URL {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        let fm = FileManager.default
        try fm.createDirectory(at: root.appendingPathComponent("Essays"), withIntermediateDirectories: true)
        try fm.createDirectory(
            at: root.appendingPathComponent(".obsidian"), withIntermediateDirectories: true)
        try "# Fast year\n\nbody".write(
            to: root.appendingPathComponent("a.md"), atomically: true, encoding: .utf8)
        try "plain first line\nmore".write(
            to: root.appendingPathComponent("b.txt"), atomically: true, encoding: .utf8)
        try "x".write(to: root.appendingPathComponent(".hidden.md"), atomically: true, encoding: .utf8)
        try "x".write(to: root.appendingPathComponent("image.png"), atomically: true, encoding: .utf8)
        try "# Nested".write(
            to: root.appendingPathComponent("Essays/c.md"), atomically: true, encoding: .utf8)
        try "x".write(
            to: root.appendingPathComponent(".obsidian/config.md"), atomically: true, encoding: .utf8)
        return root
    }
    @Test func scansSupportedFilesOnly() throws {
        let f = try Scanner.scan(root: try makeTree())
        #expect(Set(f.documents.map(\.title)) == ["Fast year", "plain first line"])
        #expect(f.folders.map(\.name) == ["Essays"])
        #expect(f.folders[0].documents.first?.title == "Nested")
        #expect(f.documentCount == 3)
    }
    @Test func typesByExtension() {
        #expect(DocumentType(url: URL(fileURLWithPath: "/x/a.MD")) == .markdown)
        #expect(DocumentType(url: URL(fileURLWithPath: "/x/a.text")) == .plainText)
        #expect(DocumentType(url: URL(fileURLWithPath: "/x/a.pdf")) == .pdf)
        #expect(DocumentType(url: URL(fileURLWithPath: "/x/a.png")) == nil)
    }
}
