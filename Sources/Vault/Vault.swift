import Foundation

public enum VaultError: Error, Equatable {
    case notEditable(DocumentType), noRoots
}

public actor Vault {
    public private(set) var roots: [URL]
    public init(roots: [URL]) { self.roots = roots }

    public func setRoots(_ urls: [URL]) { roots = urls }

    public func tree() throws -> [Folder] { try roots.map { try Scanner.scan(root: $0) } }

    public func makeNote(text: String, in folder: URL) throws -> URL {
        let existing = Set((try? FileManager.default.contentsOfDirectory(atPath: folder.path)) ?? [])
        let url = folder.appendingPathComponent(NoteName.make(from: text, taken: existing))
        try text.write(to: url, atomically: true, encoding: .utf8)
        return url
    }

    /// The file as it sits on disk, which is what the editor shows and writes back.
    /// Extraction is for reading aloud; a Markdown source edited as its own prose
    /// would come back with its formatting flattened out.
    public func rawText(of document: Document) throws -> String {
        guard document.type != .pdf else { throw VaultError.notEditable(document.type) }
        return try String(contentsOf: document.url, encoding: .utf8)
    }

    public func save(text: String, to document: Document) throws {
        guard document.type != .pdf else { throw VaultError.notEditable(document.type) }
        try text.write(to: document.url, atomically: true, encoding: .utf8)
    }
}
