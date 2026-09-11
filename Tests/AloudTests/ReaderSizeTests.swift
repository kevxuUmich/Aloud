import AloudUI
import Testing

@testable import Aloud

@Suite struct ReaderSizeTests {
    @Test func stepsStayWithinTheSizes() {
        #expect(ReaderSize.smaller(0) == 0)
        #expect(ReaderSize.larger(ReaderSize.last) == ReaderSize.last)
        #expect(ReaderSize.larger(0) == 1)
        #expect(ReaderSize.smaller(2) == 1)
    }
    /// An index left by a build with more sizes is clamped rather than trusted.
    @Test func aStaleIndexIsClamped() {
        #expect(ReaderSize.clamp(99) == ReaderSize.last)
        #expect(ReaderSize.clamp(-3) == 0)
        #expect(ReaderSize.name(99) == "Largest")
    }
    @Test func everySizeHasAName() {
        #expect(ReaderSize.names.count == Type.readerSizes.count)
    }
}
