import Foundation

public enum SourceKind: Sendable, Hashable {
    case markdown, plainText, pdf
}

public struct ExtractOptions: Sendable, Hashable {
    public var skipCode: Bool
    public init(skipCode: Bool = true) { self.skipCode = skipCode }
    public static let `default` = ExtractOptions()
}

public enum ExtractError: Error, Equatable {
    case undecodable
    case unsupported(SourceKind)
}

public protocol Extractor: Sendable {
    func script(from data: Data, options: ExtractOptions) throws -> Script
}

public enum Extractors {
    public static func extractor(for kind: SourceKind) throws -> any Extractor {
        switch kind {
        case .plainText:
            return PlainTextExtractor()
        case .markdown:
            return MarkdownExtractor()
        case .pdf:
            return PDFExtractor()
        }
    }
}

extension Data {
    func decodedText() throws -> String {
        if let s = String(data: self, encoding: .utf8) { return s }
        // A BOM-only or truncated UTF-16 fragment decodes to "" rather than
        // nil, so an empty result on non-empty data is treated as a failure.
        if !isEmpty, let s = String(data: self, encoding: .utf16), !s.isEmpty { return s }
        throw ExtractError.undecodable
    }
}

enum Paragraphs {
    /// Blank lines separate paragraphs; single line breaks inside one become spaces.
    static func normalize(_ text: String) -> String {
        text.replacingOccurrences(of: "\r\n", with: "\n")
            .components(separatedBy: "\n\n")
            .map {
                $0.split(separator: "\n").map { $0.trimmingCharacters(in: .whitespaces) }
                    .filter { !$0.isEmpty }.joined(separator: " ")
            }
            .filter { !$0.isEmpty }
            .joined(separator: "\n\n")
    }
}
