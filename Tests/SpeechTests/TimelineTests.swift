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
        let t = Timeline(script: script, rate: .x1)
        #expect(t.starts == [.zero, .seconds(6), .seconds(12)])
        #expect(t.total == .seconds(18))
    }
    @Test func indexAtTime() {
        let t = Timeline(script: script, rate: .x1)
        #expect(t.index(at: .seconds(0)) == 0)
        #expect(t.index(at: .seconds(7)) == 1)
        #expect(t.index(at: .seconds(99)) == 2)
        #expect(t.index(at: .seconds(-5)) == 0)
    }
    @Test func rateShrinksIt() {
        #expect(Timeline(script: script, rate: .x2).total == .seconds(9))
    }
}
