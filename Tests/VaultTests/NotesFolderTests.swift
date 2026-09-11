import Foundation
import Testing

@testable import Vault

@Suite struct NotesFolderTests {
    func temp() throws -> URL {
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir
    }
    @Test func theDefaultLivesInDocumentsUnderItsOwnName() {
        let docs = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
        #expect(NotesFolder.url.lastPathComponent == NotesFolder.name)
        #expect(NotesFolder.url.deletingLastPathComponent().path == docs.path)
    }
    @Test func ensureCreatesTheFolderOnceAndKeepsIt() throws {
        let dir = try temp()
        defer { try? FileManager.default.removeItem(at: dir) }
        let notes = dir.appendingPathComponent(NotesFolder.name)
        #expect(NotesFolder.ensure(notes) == notes)
        try "x".write(to: notes.appendingPathComponent("a.md"), atomically: true, encoding: .utf8)
        #expect(NotesFolder.ensure(notes) == notes)
        #expect(FileManager.default.fileExists(atPath: notes.appendingPathComponent("a.md").path))
    }
    /// A path that cannot be a folder - its parent is a file - is reported as nil
    /// rather than trusted, which is what leaves the app with no folder at all.
    @Test func ensureIsNilWhereNoFolderCanBe() throws {
        let dir = try temp()
        defer { try? FileManager.default.removeItem(at: dir) }
        let file = dir.appendingPathComponent("file")
        try "x".write(to: file, atomically: true, encoding: .utf8)
        #expect(NotesFolder.ensure(file.appendingPathComponent(NotesFolder.name)) == nil)
        #expect(NotesFolder.ensure(file) == nil)
    }
}
