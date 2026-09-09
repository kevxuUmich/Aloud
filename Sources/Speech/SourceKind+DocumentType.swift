import Prose
import Vault

extension SourceKind {
    public init(_ type: DocumentType) {
        switch type {
        case .markdown: self = .markdown
        case .plainText: self = .plainText
        case .pdf: self = .pdf
        }
    }
}
