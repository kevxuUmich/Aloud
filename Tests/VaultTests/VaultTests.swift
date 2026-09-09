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
    @Test func savesEditsAtomically() async throws {
        let root = try tempRoot()
        let vault = Vault(roots: [root])
        let url = try await vault.makeNote(text: "v1", in: root)
        let doc = try await vault.tree()[0].documents[0]
        try await vault.save(text: "v2", to: doc)
        #expect(try String(contentsOf: url, encoding: .utf8) == "v2")
    }
    @Test func refusesToSavePDF() async throws {
        let root = try tempRoot()
        let vault = Vault(roots: [root])
        let pdf = Document(
            url: root.appendingPathComponent("x.pdf"), title: "x", preview: "", modified: .now,
            bytes: 0, type: .pdf)
        await #expect(throws: VaultError.self) { try await vault.save(text: "no", to: pdf) }
    }
}
