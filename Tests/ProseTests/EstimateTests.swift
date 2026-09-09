import Testing

@testable import Prose

@Suite struct EstimateTests {
    @Test func oneSixtyWordsIsOneMinute() {
        #expect(Estimate.duration(words: 160, factor: 1) == .seconds(60))
    }
    @Test func doubleRateHalvesIt() {
        #expect(Estimate.duration(words: 160, factor: 2) == .seconds(30))
    }
    @Test func zeroWordsIsZero() {
        #expect(Estimate.duration(words: 0, factor: 1.25) == .zero)
    }
    @Test func countsWords() {
        #expect(Estimate.words(in: "it's a stack of smaller skills, and almost") == 8)
    }
}
