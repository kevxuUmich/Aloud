import Testing

@testable import Speech

@Suite struct PausesTests {
    @Test func theStandardBeats() {
        #expect(Pauses.standard.sentence == .milliseconds(200))
        #expect(Pauses.standard.paragraph == .milliseconds(300))
    }
    @Test func labelsInSeconds() {
        #expect(Pauses.label(.milliseconds(200)) == "0.2 s")
        #expect(Pauses.label(.milliseconds(250)) == "0.25 s")
        #expect(Pauses.label(.zero) == "0.0 s")
    }
}
