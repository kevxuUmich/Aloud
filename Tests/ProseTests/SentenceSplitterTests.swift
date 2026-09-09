import Testing

@testable import Prose

@Suite struct SentenceSplitterTests {
    @Test func splitsSentencesAndKeepsRanges() {
        let s = "Nobody teaches you research. You get a desk.\n\nPick your own problems"
        let out = SentenceSplitter.split(s)
        #expect(
            out.map(\.text) == ["Nobody teaches you research.", "You get a desk.", "Pick your own problems"])
        for sen in out { #expect(String(s[sen.range]) == sen.text) }
    }
    @Test func paragraphEndEndsASentence() {
        let out = SentenceSplitter.split("a heading without a period\n\nthe body. more body.")
        #expect(out.first?.text == "a heading without a period")
        #expect(out.count == 3)
    }
    @Test func emptyIsEmpty() {
        #expect(SentenceSplitter.split("  \n\n ").isEmpty)
    }
    @Test func scriptCountsWords() {
        let sc = Script(
            source: "one two three. four five.",
            sentences: SentenceSplitter.split("one two three. four five."))
        #expect(sc.wordCount == 5)
    }
}
