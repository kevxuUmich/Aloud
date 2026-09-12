import AppKit
import Testing

@testable import Aloud

/// What a key does while the clipboard panel is key: the table the window's monitor
/// reads, tested here without a window.
@Suite struct PanelKeysTests {
    @Test func bareKeysMapToTheirActions() {
        #expect(PanelKeys.action(keyCode: PanelKeys.escape, modifiers: []) == .dismiss)
        #expect(PanelKeys.action(keyCode: PanelKeys.enter, modifiers: []) == .play)
        #expect(PanelKeys.action(keyCode: PanelKeys.keypadEnter, modifiers: []) == .play)
        #expect(PanelKeys.action(keyCode: PanelKeys.space, modifiers: []) == .play)
        #expect(PanelKeys.action(keyCode: PanelKeys.up, modifiers: []) == .faster)
        #expect(PanelKeys.action(keyCode: PanelKeys.down, modifiers: []) == .slower)
    }

    /// An arrow key's event carries the function and numeric-pad flags of its own
    /// accord; they are the key's, not a modifier the listener held.
    @Test func arrowsArriveWithTheirOwnFlags() {
        #expect(PanelKeys.action(keyCode: PanelKeys.up, modifiers: [.function, .numericPad]) == .faster)
        #expect(PanelKeys.action(keyCode: PanelKeys.down, modifiers: [.function, .numericPad]) == .slower)
    }

    /// A modifier makes the keystroke a menu's, so it is left alone; so is any other key.
    @Test func modifiedAndOtherKeysAreLeftAlone() {
        #expect(PanelKeys.action(keyCode: PanelKeys.space, modifiers: [.command]) == nil)
        #expect(PanelKeys.action(keyCode: PanelKeys.up, modifiers: [.option]) == nil)
        #expect(PanelKeys.action(keyCode: 0, modifiers: []) == nil)
    }
}
