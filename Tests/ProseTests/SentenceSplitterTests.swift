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
        let s = "see e.g. the appendix. then stop."
        let out = SentenceSplitter.split(s)
        #expect(out.map(\.text) == ["see e.g. the appendix.", "then stop."])
        for sen in out { #expect(String(s[sen.range]) == sen.text) }
    }
    @Test func titleAbbreviationDoesNotEndASentence() {
        let out = SentenceSplitter.split("dr. hamming asked. people left.")
        #expect(out.map(\.text) == ["dr. hamming asked.", "people left."])
    }
    @Test func singleLetterInitialDoesNotEndASentence() {
        let out = SentenceSplitter.split("j. schulman's guide. two modes.")
        #expect(out.map(\.text) == ["j. schulman's guide.", "two modes."])
    }
    @Test func noBeforeADigitDoesNotEndASentence() {
        let out = SentenceSplitter.split("issue no. 5 shipped. done.")
        #expect(out.map(\.text) == ["issue no. 5 shipped.", "done."])
    }
    @Test func noBeforeAWordEndsASentence() {
        let out = SentenceSplitter.split("the answer was no. we left.")
        #expect(out.map(\.text) == ["the answer was no.", "we left."])
    }
    @Test func closingQuoteStillEndsASentence() {
        let out = SentenceSplitter.split("he said 'stop.' then left.")
        #expect(out.map(\.text) == ["he said 'stop.'", "then left."])
    }
    @Test func parenthesizedAbbreviationDoesNotEndASentence() {
        let out = SentenceSplitter.split("results (e.g. cats) matter. next.")
        #expect(out.map(\.text) == ["results (e.g. cats) matter.", "next."])
    }
    @Test func quotedAbbreviationDoesNotEndASentence() {
        let out = SentenceSplitter.split("\"dr. smith\" spoke. done.")
        #expect(out.map(\.text) == ["\"dr. smith\" spoke.", "done."])
    }
}
