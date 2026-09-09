import Foundation
import Testing

@testable import Vault

@Suite struct TrashTests {
    @Test func movesTheFileOut() throws {
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        let url = dir.appendingPathComponent("gone.md")
        try "bye".write(to: url, atomically: true, encoding: .utf8)
        let doc = Document(url: url, title: "gone", preview: "", modified: .now, bytes: 3, type: .markdown)
        let moved = try Trash.move(doc)
        #expect(!FileManager.default.fileExists(atPath: url.path))
        #expect(FileManager.default.fileExists(atPath: moved.path))
        try? FileManager.default.removeItem(at: moved)
    }
}
