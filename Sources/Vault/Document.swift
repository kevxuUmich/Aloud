import Foundation

public struct Document: Identifiable, Hashable, Sendable {
    public var id: String { url.path }
    public let url: URL
    public let title: String
    public let preview: String
    public let modified: Date
    public let bytes: Int
    public let type: DocumentType
    public init(
        url: URL, title: String, preview: String, modified: Date, bytes: Int, type: DocumentType
    ) {
        self.url = url
        self.title = title
        self.preview = preview
        self.modified = modified
        self.bytes = bytes
        self.type = type
    }
}

public struct Folder: Identifiable, Hashable, Sendable {
    public var id: String { url.path }
    public let url: URL
    public let name: String
    public let folders: [Folder]
    public let documents: [Document]
    public var documentCount: Int {
        documents.count + folders.reduce(0) { $0 + $1.documentCount }
    }
    public init(url: URL, name: String, folders: [Folder], documents: [Document]) {
        self.url = url
        self.name = name
        self.folders = folders
        self.documents = documents
    }
}
