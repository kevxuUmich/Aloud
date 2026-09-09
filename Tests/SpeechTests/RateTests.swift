import Testing

@testable import Speech

@Suite struct RateTests {
    @Test func labelsDropTrailingZeros() {
        #expect(Rate.x1.label == "1x"); #expect(Rate.x125.label == "1.25x"); #expect(Rate.x15.label == "1.5x")
    }
    @Test func cyclesAndWraps() {
        #expect(Rate.x1.next == .x125); #expect(Rate.x3.next == .x075)
    }
    @Test func appleRateIsDefaultAtOneAndMaxAtThree() {
        #expect(Rate.x1.appleRate == 0.5)
        #expect(Rate.x3.appleRate == 1.0)
        #expect(Rate.x075.appleRate == 0.375)
        #expect(Rate.x2.appleRate == 0.75)
    }
    @Test func eightSteps() { #expect(Rate.allCases.count == 8) }
    @Test func labelsAreLocaleIndependent() {
        #expect(
            Rate.allCases.map(\.label) == [
                "0.75x", "1x", "1.25x", "1.5x", "1.75x", "2x", "2.5x", "3x",
            ])
    }
}
