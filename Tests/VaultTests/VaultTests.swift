import Foundation
import Testing

@testable import Vault

@Suite struct VaultTests {
    func tempRoot() throws -> URL {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        return root
    }
    @Test func makesANoteAndSeesItInTheTree() async throws {
        let root = try tempRoot()
        let vault = Vault(roots: [root])
        let url = try await vault.makeNote(text: "Hello there.\n\nMore.", in: root)
        #expect(url.lastPathComponent == "Hello there.md")
        let tree = try await vault.tree()
        #expect(tree[0].documents.first?.title == "Hello there.")
    }
    /// The same text again is the note already on disk, not a numbered second file;
    /// a different note under the same title, and a note edited since, are their own.
    @Test func theSameTextAgainIsTheNoteAlreadyWritten() async throws {
        let root = try tempRoot()
        let vault = Vault(roots: [root])
        let first = try await vault.makeNote(text: "Hello there.\n\nMore.", in: root)
        let again = try await vault.makeNote(text: "Hello there.\n\nMore.", in: root)
        #expect(again == first)
        let other = try await vault.makeNote(text: "Hello there.\n\nElse.", in: root)
        #expect(other.lastPathComponent == "Hello there 2.md")
        let otherAgain = try await vault.makeNote(text: "Hello there.\n\nElse.", in: root)
        #expect(otherAgain == other)
        try "Hello there.\n\nEdited.".write(to: first, atomically: true, encoding: .utf8)
        let third = try await vault.makeNote(text: "Hello there.\n\nMore.", in: root)
        #expect(third.lastPathComponent == "Hello there 3.md")
        #expect(try FileManager.default.contentsOfDirectory(atPath: root.path).count == 3)
    }
    @Test func savesEditsAtomically() async throws {
        let root = try tempRoot()
        let vault = Vault(roots: [root])
        let url = try await vault.makeNote(text: "v1", in: root)
        let doc = try await vault.tree()[0].documents[0]
        try await vault.save(text: "v2", to: doc)
        #expect(try String(contentsOf: url, encoding: .utf8) == "v2")
        #expect(await vault.writes == 1)
    }
    @Test func refusesToSavePDF() async throws {
        let root = try tempRoot()
        let vault = Vault(roots: [root])
        let pdf = Document(
            url: root.appendingPathComponent("x.pdf"), title: "x", preview: "", modified: .now,
            bytes: 0, type: .pdf)
        await #expect(throws: VaultError.self) { try await vault.save(text: "no", to: pdf) }
    }
    @Test func rawTextIsTheFileNotTheProse() async throws {
        let root = try tempRoot()
        let vault = Vault(roots: [root])
        let url = try await vault.makeNote(text: "# Title\n\nSome *emphasis*.", in: root)
        let doc = try await vault.tree()[0].documents[0]
        #expect(try await vault.rawText(of: doc) == "# Title\n\nSome *emphasis*.")
        let pdf = Document(
            url: url.deletingLastPathComponent().appendingPathComponent("x.pdf"), title: "x",
            preview: "", modified: .now, bytes: 0, type: .pdf)
        await #expect(throws: VaultError.self) { try await vault.rawText(of: pdf) }
    }
}

/// A rename is a change to the title the library shows, which for a note lives in
/// the text and for a PDF lives in the filename.
@Suite struct VaultRenameTests {
    func tempRoot() throws -> URL {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        return root
    }
    @Test func renamingANoteRewritesItsTitleLineInPlace() async throws {
        let root = try tempRoot()
        let vault = Vault(roots: [root])
        let url = try await vault.makeNote(text: "# Old\n\nBody.", in: root)
        let doc = try await vault.tree()[0].documents[0]
        let renamed = try await vault.rename(doc, to: "New")
        #expect(renamed.url == doc.url)
        #expect(renamed.title == "New")
        #expect(try String(contentsOf: url, encoding: .utf8) == "# New\n\nBody.")
        #expect(try await vault.tree()[0].documents[0].title == "New")
    }
    @Test func renamingAPDFMovesTheFile() async throws {
        let root = try tempRoot()
        let vault = Vault(roots: [root])
        let url = root.appendingPathComponent("old.pdf")
        try Data("%PDF".utf8).write(to: url)
        let pdf = Document(url: url, title: "old", preview: "", modified: .now, bytes: 4, type: .pdf)
        let renamed = try await vault.rename(pdf, to: "New name")
        #expect(renamed.url == root.appendingPathComponent("New name.pdf"))
        #expect(renamed.title == "New name")
        #expect(!FileManager.default.fileExists(atPath: url.path))
        #expect(FileManager.default.fileExists(atPath: renamed.url.path))
    }
    @Test func renamingAPDFOntoATakenNameThrows() async throws {
        let root = try tempRoot()
        let vault = Vault(roots: [root])
        for n in ["a.pdf", "b.pdf"] { try Data("%PDF".utf8).write(to: root.appendingPathComponent(n)) }
        let a = Document(
            url: root.appendingPathComponent("a.pdf"), title: "a", preview: "", modified: .now,
            bytes: 4, type: .pdf)
        await #expect(throws: VaultError.self) { try await vault.rename(a, to: "b") }
    }
    @Test func aBlankNameIsRefused() async throws {
        let root = try tempRoot()
        let vault = Vault(roots: [root])
        _ = try await vault.makeNote(text: "# Old", in: root)
        let doc = try await vault.tree()[0].documents[0]
        await #expect(throws: VaultError.self) { try await vault.rename(doc, to: "  ") }
    }
}

/// A note the panel wrote keeps where its text came from, in front matter the scanner
/// reads back and the text is compared without.
@Suite struct VaultOriginTests {
    func tempRoot() throws -> URL {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        return url
    }
    let safari = Origin(
        app: "Safari", bundle: "com.apple.Safari",
        page: .init(url: URL(string: "https://example.com/a")!, title: "Example"))

    @Test func theOriginIsWrittenAsFrontMatterAndScannedBack() async throws {
        let root = try tempRoot()
        let vault = Vault(roots: [root])
        let url = try await vault.makeNote(text: "# Hello\n\nBody.", origin: safari, in: root)
        #expect(try String(contentsOf: url, encoding: .utf8) == safari.frontMatter + "# Hello\n\nBody.")
        let doc = try await vault.tree()[0].documents[0]
        #expect(doc.origin == safari)
        #expect(doc.title == "Hello")
        #expect(doc.preview == "# Hello\n\nBody.")
    }

    @Test func theSameTextFromAnywhereIsTheNoteAlreadyWritten() async throws {
        let root = try tempRoot()
        let vault = Vault(roots: [root])
        let first = try await vault.makeNote(text: "Hello.\n\nMore.", origin: safari, in: root)
        let notes = Origin(app: "Notes", bundle: "com.apple.Notes")
        #expect(try await vault.makeNote(text: "Hello.\n\nMore.", origin: notes, in: root) == first)
        #expect(try await vault.makeNote(text: "Hello.\n\nMore.", in: root) == first)
        #expect(try await vault.tree()[0].documents[0].origin == safari)
    }

    @Test func aRenameKeepsTheOrigin() async throws {
        let root = try tempRoot()
        let vault = Vault(roots: [root])
        let url = try await vault.makeNote(text: "# Old\n\nBody.", origin: safari, in: root)
        let doc = try await vault.tree()[0].documents[0]
        let renamed = try await vault.rename(doc, to: "New")
        #expect(renamed.origin == safari)
        #expect(try String(contentsOf: url, encoding: .utf8) == safari.frontMatter + "# New\n\nBody.")
    }
}
