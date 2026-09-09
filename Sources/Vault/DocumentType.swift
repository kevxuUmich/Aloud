import Foundation

public enum DocumentType: Sendable, Hashable {
    case markdown, plainText, pdf
    public init?(url: URL) {
        switch url.pathExtension.lowercased() {
        case "md", "markdown": self = .markdown
        case "txt", "text": self = .plainText
        case "pdf": self = .pdf
        default: return nil
        }
    }
}
