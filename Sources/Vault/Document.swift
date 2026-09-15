import Foundation

public struct Document: Identifiable, Hashable, Sendable {
    public var id: String { url.path }
    public let url: URL
    public let title: String
    public let preview: String
    public let modified: Date
    public let bytes: Int
    public let type: DocumentType
    /// Where the text came from, for a note the panel wrote: read from its front
    /// matter. Nil for every file that was simply in the folder.
    public let origin: Origin?
    public init(
        url: URL, title: String, preview: String, modified: Date, bytes: Int, type: DocumentType,
        origin: Origin? = nil
    ) {
        self.url = url
        self.title = title
        self.preview = preview
        self.modified = modified
        self.bytes = bytes
        self.type = type
        self.origin = origin
    }
}

public struct Folder: Identifiable, Hashable, Sendable {
    public var id: String { url.path }
    public let url: URL
    public let name: String
    public let folders: [Folder]
    public let documents: [Document]
    public let unreadable: [URL]
    public var documentCount: Int {
        documents.count + folders.reduce(0) { $0 + $1.documentCount }
    }
    public init(
        url: URL, name: String, folders: [Folder], documents: [Document], unreadable: [URL] = []
    ) {
        self.url = url
        self.name = name
        self.folders = folders
        self.documents = documents
        self.unreadable = unreadable
    }
}
