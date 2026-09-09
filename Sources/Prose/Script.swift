import Foundation

public struct Sentence: Hashable, Sendable {
    public let text: String
    public let range: Range<String.Index>
    public init(text: String, range: Range<String.Index>) {
        self.text = text
        self.range = range
    }
}

public struct Script: Hashable, Sendable {
    public let source: String
    public let sentences: [Sentence]
    public let wordCount: Int
    public init(source: String, sentences: [Sentence]) {
        self.source = source
        self.sentences = sentences
        self.wordCount = sentences.reduce(0) { $0 + Estimate.words(in: $1.text) }
    }
    public static let empty = Script(source: "", sentences: [])

    /// The sentence containing a UTF-16 offset into `source`, which is what a text
    /// view reports for a click. Nil when the offset is outside the source, so a
    /// click past the end is ignored rather than seeking to the last sentence.
    public func sentenceIndex(atUTF16Offset offset: Int) -> Int? {
        guard offset >= 0, offset < source.utf16.count,
            let idx = Range(NSRange(location: offset, length: 0), in: source)?.lowerBound
        else { return nil }
        return sentences.lastIndex { $0.range.lowerBound <= idx }
    }
}
