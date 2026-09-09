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
    @Test func abbreviationDoesNotEndASentence() {
        let out = SentenceSplitter.split("see e.g. the appendix. then stop.")
        #expect(out.count == 2)
    }
    @Test func titleAbbreviationDoesNotEndASentence() {
        let out = SentenceSplitter.split("dr. hamming asked. people left.")
        #expect(out.count == 2)
    }
    @Test func singleLetterInitialDoesNotEndASentence() {
        let out = SentenceSplitter.split("j. schulman's guide. two modes.")
        #expect(out.count == 2)
    }
    @Test func noBeforeADigitDoesNotEndASentence() {
        let out = SentenceSplitter.split("issue no. 5 shipped. done.")
        #expect(out.count == 2)
    }
    @Test func noBeforeAWordEndsASentence() {
        let out = SentenceSplitter.split("the answer was no. we left.")
        #expect(out.count == 2)
    }
    @Test func closingQuoteStillEndsASentence() {
        let out = SentenceSplitter.split("he said 'stop.' then left.")
        #expect(out.count == 2)
    }
}
