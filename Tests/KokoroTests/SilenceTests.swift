import Testing

@testable import Kokoro

@Suite struct SilenceTests {
    /// Silence is anything under the threshold; `margin` samples of it are kept on
    /// each side of the speech.
    @Test func trimsTheSilenceAroundTheSpeechAndKeepsAMargin() {
        let quiet = [Float](repeating: 0.001, count: 100)
        let loud = [Float](repeating: 0.5, count: 10)
        let trimmed = Silence.trim(quiet + loud + quiet, threshold: 0.002, margin: 3)
        #expect(trimmed.count == 16)
        #expect(trimmed[0] == 0.001)
        #expect(trimmed[3] == 0.5)
        #expect(trimmed[12] == 0.5)
        #expect(trimmed[15] == 0.001)
    }

    /// Speech that starts or ends at the edge has less than a margin of silence there,
    /// and what there is comes back rather than reading past the ends.
    @Test func theMarginIsClampedAtTheEnds() {
        let loud = [Float](repeating: 0.5, count: 5)
        #expect(Silence.trim(loud, threshold: 0.002, margin: 3) == loud)
        #expect(Silence.trim([0, 0] + loud, threshold: 0.002, margin: 3).count == 7)
    }

    /// Nothing above the threshold is nothing to hear.
    @Test func allSilenceComesBackEmpty() {
        #expect(Silence.trim([Float](repeating: 0.001, count: 50), threshold: 0.002, margin: 3).isEmpty)
        #expect(Silence.trim([], threshold: 0.002, margin: 3).isEmpty)
    }

    /// Negative samples count as loud too.
    @Test func amplitudeIsAbsolute() {
        #expect(Silence.trim([0, 0, -0.5, 0, 0], threshold: 0.002, margin: 1) == [0, -0.5, 0])
    }

    /// The defaults are the measured ones: the model's silence sits within a few
    /// thousandths of zero, and 30 ms at 24 kHz clips no onset.
    @Test func theDefaultsAreTheMeasuredOnes() {
        #expect(Silence.threshold == 0.002)
        #expect(Silence.margin == 720)
    }
}
