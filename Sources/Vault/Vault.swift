import Foundation
import Prose

public enum VaultError: LocalizedError, Equatable {
    case notEditable(DocumentType), noRoots, blankName, nameTaken(String)
    public var errorDescription: String? {
        switch self {
        case .notEditable: "this kind of file cannot be edited"
        case .noRoots: "no folder is attached"
        case .blankName: "the name is empty"
        case .nameTaken(let name): "a file named \(name) is already there"
        }
    }
}

public actor Vault {
    public private(set) var roots: [URL]
    /// How many edits this vault has written. The rule that a blur and the Done click
    /// that follows it write once is invisible from outside without it: the file ends
    /// up holding the same text either way.
    public private(set) var writes = 0
    public init(roots: [URL]) { self.roots = roots }

    public func setRoots(_ urls: [URL]) { roots = urls }

    public func tree() throws -> [Folder] { try roots.map { try Scanner.scan(root: $0) } }

    /// Text already written into the folder is the note it became, not a numbered
    /// second file: the same paragraph pasted twice is one note. Only the files this
    /// text would be named after are read, the title's own name and its numbered
    /// siblings, so the check costs a few reads and not the folder. A note edited since
    /// it was pasted no longer reads the same and is left as its own.
    public func makeNote(text: String, in folder: URL) throws -> URL {
        let existing = Set((try? FileManager.default.contentsOfDirectory(atPath: folder.path)) ?? [])
        for name in NoteName.siblings(of: text, among: existing) {
            let url = folder.appendingPathComponent(name)
            if (try? String(contentsOf: url, encoding: .utf8)) == text { return url }
        }
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

    /// The document under its new title: the title line rewritten for text, the file
    /// moved for a PDF, whose title is its filename. The returned document is the one
    /// the caller should hold from now on, since a PDF's URL changes.
    public func rename(_ document: Document, to title: String) throws -> Document {
        let clean = title.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !clean.isEmpty else { throw VaultError.blankName }
        guard document.type == .pdf else {
            let text = Title.retitle(text: try rawText(of: document), to: clean)
            try save(text: text, to: document)
            return Document(
                url: document.url, title: Title.from(text: text, fallback: clean),
                preview: FrontMatter.strip(text), modified: .now, bytes: text.utf8.count,
                type: document.type)
        }
        let name = NoteName.fileName(for: clean, extension: document.url.pathExtension)
        let target = document.url.deletingLastPathComponent().appendingPathComponent(name)
        guard target.path != document.url.path else { return document }
        guard !FileManager.default.fileExists(atPath: target.path) else {
            throw VaultError.nameTaken(name)
        }
        try FileManager.default.moveItem(at: document.url, to: target)
        return Document(
            url: target, title: target.deletingPathExtension().lastPathComponent, preview: "",
            modified: .now, bytes: document.bytes, type: .pdf)
    }

    public func save(text: String, to document: Document) throws {
        guard document.type != .pdf else { throw VaultError.notEditable(document.type) }
        try text.write(to: document.url, atomically: true, encoding: .utf8)
        writes += 1
    }
}
