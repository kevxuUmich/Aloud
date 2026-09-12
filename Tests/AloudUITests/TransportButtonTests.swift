import Testing

@testable import AloudUI

@Suite struct TransportButtonTests {
    /// The glyph carries the number, so the symbol is picked by the interval the button
    /// actually skips: a 10 second step drawn with a 15 in it would lie.
    @Test func theSkipGlyphSaysTheInterval() {
        #expect(TransportButton(.back, skipSeconds: 10) {}.symbol == "10.arrow.trianglehead.counterclockwise")
        #expect(TransportButton(.forward, skipSeconds: 10) {}.symbol == "10.arrow.trianglehead.clockwise")
        #expect(TransportButton(.forward, skipSeconds: 10) {}.label == "Forward 10 seconds")
        #expect(TransportButton.defaultSkipSeconds == 10)
    }
}
