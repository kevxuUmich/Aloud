import AppKit

/// What a bare key does while the clipboard panel is key. Enter and Space play,
/// Escape dismisses, and the arrows step the speed. A table rather than a switch in
/// the window's monitor so the mapping can be read, and tested, without a window.
///
/// Bare keys only: a modifier makes the keystroke a menu's, and Cmd+Return or
/// Ctrl+Space would be swallowed here rather than doing what they do everywhere else.
enum PanelKeys {
    enum Action: Equatable { case dismiss, play, faster, slower }

    /// The virtual key codes the monitor reads. Carbon's names, without Carbon.
    static let escape: UInt16 = 53
    static let enter: UInt16 = 36
    static let keypadEnter: UInt16 = 76
    static let space: UInt16 = 49
    static let up: UInt16 = 126
    static let down: UInt16 = 125

    static func action(keyCode: UInt16, modifiers: NSEvent.ModifierFlags) -> Action? {
        guard modifiers.intersection(.deviceIndependentFlagsMask).isEmpty else { return nil }
        switch keyCode {
        case escape: return .dismiss
        case enter, keypadEnter, space: return .play
        case up: return .faster
        case down: return .slower
        default: return nil
        }
    }
}
