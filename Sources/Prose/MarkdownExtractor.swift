import Foundation

public struct MarkdownExtractor: Extractor {
    public init() {}
    public func script(from data: Data, options: ExtractOptions) throws -> Script { .empty }
}
