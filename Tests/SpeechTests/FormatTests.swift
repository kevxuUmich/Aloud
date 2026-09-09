import Testing

@testable import Speech

@Suite struct FormatTests {
    @Test func clockUnderAMinute() {
        #expect(Format.clock(.seconds(34)) == "0:34")
    }
    @Test func clockUnderAnHour() {
        #expect(Format.clock(.seconds(486)) == "8:06")
    }
    @Test func clockOverAnHour() {
        #expect(Format.clock(.seconds(3661)) == "1:01:01")
    }
    @Test func clockClampsNegativeToZero() {
        #expect(Format.clock(.seconds(-5)) == "0:00")
    }
    @Test func minutesRoundsUpFromHalf() {
        #expect(Format.minutes(.seconds(30)) == "1 min")
    }
    @Test func minutesRoundsToNearest() {
        #expect(Format.minutes(.seconds(486)) == "8 min")
    }
}
