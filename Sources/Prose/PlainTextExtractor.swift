import Foundation

public struct PlainTextExtractor: Extractor {
    public init() {}
    public func script(from data: Data, options: ExtractOptions) throws -> Script {
        let source = Paragraphs.normalize(try data.decodedText())
        return Script(source: source, sentences: SentenceSplitter.split(source))
    }
}
