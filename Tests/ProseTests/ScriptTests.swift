import Foundation
import Testing

@testable import Prose

@Suite struct ScriptTests {
    /// A sentence ends a paragraph when a line break stands between it and the next;
    /// the last sentence ends nothing, since nothing follows it.
    @Test func endsParagraphWhereALineBreakFollows() {
        let source = "One two. Three four.\n\nFive six.\nSeven eight."
        let script = Script(source: source, sentences: SentenceSplitter.split(source))
        #expect(script.sentences.count == 4)
        #expect(script.endsParagraph(at: 0) == false)
        #expect(script.endsParagraph(at: 1) == true)
        #expect(script.endsParagraph(at: 2) == true)
        #expect(script.endsParagraph(at: 3) == false)
        #expect(script.endsParagraph(at: 9) == false)
    }

    static let fixture = URL(fileURLWithPath: #filePath)
        .deletingLastPathComponent().appendingPathComponent("Fixtures/essay.md")

    static func essay() throws -> Script {
        try Extractors.extractor(for: .markdown)
            .script(from: try Data(contentsOf: fixture), options: .default)
    }

    @Test func everyOffsetInASentenceMapsBackToIt() throws {
        let script = try Self.essay()
        #expect(script.sentences.count > 1)
        for (i, s) in script.sentences.enumerated() {
            let ns = NSRange(s.range, in: script.source)
            for offset in [ns.location, ns.location + ns.length / 2, ns.location + max(ns.length - 1, 0)] {
                #expect(
                    script.sentenceIndex(atUTF16Offset: offset) == i,
                    "offset \(offset) should be in sentence \(i)")
            }
        }
    }

    @Test func offsetsOutsideTheSourceAreNil() throws {
        let script = try Self.essay()
        #expect(script.sentenceIndex(atUTF16Offset: -1) == nil)
        #expect(script.sentenceIndex(atUTF16Offset: script.source.utf16.count) == nil)
        #expect(script.sentenceIndex(atUTF16Offset: script.source.utf16.count + 100) == nil)
        #expect(script.sentenceIndex(atUTF16Offset: 0) == 0)
    }

    @Test func theEmptyScriptHasNoSentenceAnywhere() {
        #expect(Script.empty.sentenceIndex(atUTF16Offset: 0) == nil)
    }

    @Test func anOffsetInsideAMultiByteCharacterSnapsToItsSentence() {
        // "Hello. 🐈 world." - the cat is a surrogate pair, so its second UTF-16 unit
        // is not a character boundary. `Range(_:in:)` rounds such an offset out to
        // the enclosing character rather than failing, so both halves of the pair
        // answer with the sentence the cat is in.
        let source = "Hello. 🐈 world."
        let ns = source as NSString
        let first = source.startIndex..<source.index(source.startIndex, offsetBy: 6)
        let rest = source.index(source.startIndex, offsetBy: 7)..<source.endIndex
        let script = Script(
            source: source,
            sentences: [
                Sentence(text: String(source[first]), range: first),
                Sentence(text: String(source[rest]), range: rest),
            ])
        let cat = ns.range(of: "🐈").location
        #expect(script.sentenceIndex(atUTF16Offset: cat) == 1)
        #expect(script.sentenceIndex(atUTF16Offset: cat + 1) == 1)
        #expect(script.sentenceIndex(atUTF16Offset: 0) == 0)
    }
}
