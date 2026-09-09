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
}
