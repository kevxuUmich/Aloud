import Prose
import Testing

@testable import Speech

@Suite struct TimelineTests {
    // 160 words per minute at 1x, so each 16-word sentence is 6 seconds.
    let script: Script = {
        let sentence = Array(repeating: "word", count: 16).joined(separator: " ") + "."
        let source = [sentence, sentence, sentence].joined(separator: " ")
        return Script(source: source, sentences: SentenceSplitter.split(source))
    }()
    @Test func startsAccumulate() {
        let t = Timeline(script: script, rate: .x1, pauses: .none)
        #expect(t.starts == [.zero, .seconds(6), .seconds(12)])
        #expect(t.total == .seconds(18))
    }
    @Test func indexAtTime() {
        let t = Timeline(script: script, rate: .x1, pauses: .none)
        #expect(t.index(at: .seconds(0)) == 0)
        #expect(t.index(at: .seconds(7)) == 1)
        #expect(t.index(at: .seconds(99)) == 2)
        #expect(t.index(at: .seconds(-5)) == 0)
    }
    @Test func rateShrinksIt() {
        #expect(Timeline(script: script, rate: .x2, pauses: .none).total == .seconds(9))
    }
    /// The pauses are counted, each after the sentence it follows, the paragraph's
    /// where a paragraph ends, and none after the last; and they do not shrink with
    /// the rate.
    @Test func pausesAreCountedAndDoNotScale() {
        let sentence = Array(repeating: "word", count: 16).joined(separator: " ") + "."
        let source = [sentence, sentence].joined(separator: " ") + "\n\n" + sentence
        let s = Script(source: source, sentences: SentenceSplitter.split(source))
        let pauses = Pauses(sentence: .seconds(1), paragraph: .seconds(2))
        let t = Timeline(script: s, rate: .x1, pauses: pauses)
        #expect(t.starts == [.zero, .seconds(7), .seconds(15)])
        #expect(t.total == .seconds(21))
        #expect(t.duration(at: 0) == .seconds(7))
        #expect(t.duration(at: 2) == .seconds(6))
        #expect(Timeline(script: s, rate: .x2, pauses: pauses).total == .seconds(12))
    }
}
