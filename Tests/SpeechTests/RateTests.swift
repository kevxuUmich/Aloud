import AVFoundation
import Testing

@testable import Speech

@Suite struct RateTests {
    @Test func labelsDropTrailingZeros() {
        #expect(Rate.x1.label == "1x"); #expect(Rate.x125.label == "1.25x"); #expect(Rate.x15.label == "1.5x")
    }
    @Test func appleRateIsDefaultAtOneAndMaxAtThree() {
        #expect(Rate.x1.appleRate == 0.5)
        #expect(Rate.x3.appleRate == 1.0)
        #expect(Rate.x075.appleRate == 0.375)
        #expect(Rate.x05.appleRate == 0.25)
        #expect(Rate.x2.appleRate == 0.75)
    }
    /// The spec's mapping, stated against the constant rather than against 0.5.
    @Test func oneXIsTheSystemDefaultRate() {
        #expect(Rate.x1.appleRate == AVSpeechUtteranceDefaultSpeechRate)
    }
    /// A quarter apart from end to end, so an arrow key's step is the same step
    /// everywhere on the band.
    @Test func elevenStepsAQuarterApart() {
        #expect(Rate.allCases.count == 11)
        let gaps = zip(Rate.allCases.dropFirst(), Rate.allCases).map { $0.factor - $1.factor }
        #expect(gaps.allSatisfy { abs($0 - 0.25) < 0.0001 })
    }
    @Test func labelsAreLocaleIndependent() {
        #expect(
            Rate.allCases.map(\.label) == [
                "0.5x", "0.75x", "1x", "1.25x", "1.5x", "1.75x", "2x", "2.25x", "2.5x", "2.75x", "3x",
            ])
    }
    /// The arrow keys' steps: one case up or down, and the ends stay put rather than
    /// wrapping, since a key held down should not jump from fastest to slowest.
    @Test func fasterAndSlowerStopAtTheEnds() {
        #expect(Rate.x1.faster == .x125)
        #expect(Rate.x125.slower == .x1)
        #expect(Rate.x3.faster == .x3)
        #expect(Rate.x05.slower == .x05)
    }
}
