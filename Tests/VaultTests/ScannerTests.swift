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

    func makeEmptyRoot() throws -> URL {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        return root
    }

    @Test func symlinkLoopsDoNotHang() throws {
        let root = try makeEmptyRoot()
        let fm = FileManager.default
        try fm.createDirectory(at: root.appendingPathComponent("a"), withIntermediateDirectories: true)
        try "# Doc".write(
            to: root.appendingPathComponent("a/note.md"), atomically: true, encoding: .utf8)
        try fm.createSymbolicLink(
            atPath: root.appendingPathComponent("a/loop").path, withDestinationPath: "..")
        let f = try Scanner.scan(root: root)
        #expect(f.documentCount == 1)
    }

    @Test func unreadableSubfolderIsSkippedAndRecorded() throws {
        let root = try makeEmptyRoot()
        let fm = FileManager.default
        try "# Ok".write(to: root.appendingPathComponent("ok.md"), atomically: true, encoding: .utf8)
        let blocked = root.appendingPathComponent("Blocked")
        try fm.createDirectory(at: blocked, withIntermediateDirectories: true)
        try "x".write(to: blocked.appendingPathComponent("x.md"), atomically: true, encoding: .utf8)
        try fm.setAttributes([.posixPermissions: 0o000], ofItemAtPath: blocked.path)
        defer { try? fm.setAttributes([.posixPermissions: 0o755], ofItemAtPath: blocked.path) }
        guard getuid() != 0 else {
            // Root ignores POSIX permissions, so the unreadable folder is readable anyway;
            // nothing to assert under this account.
            return
        }
        let f = try Scanner.scan(root: root)
        #expect(f.unreadable.map(\.lastPathComponent) == ["Blocked"])
        #expect(f.documents.map(\.title) == ["Ok"])
    }
}
