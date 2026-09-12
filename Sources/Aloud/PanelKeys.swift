import AppKit

/// What a key does while the clipboard panel is key. Enter and Space play, Escape
/// dismisses, the arrows step the volume and with Option held the speed. A table
/// rather than a switch in the window's monitor so the mapping can be read, and
/// tested, without a window.
///
/// Any other modifier makes the keystroke a menu's, and Cmd+Return or Ctrl+Space
/// would be swallowed here rather than doing what they do everywhere else.
enum PanelKeys {
    enum Action: Equatable { case dismiss, play, faster, slower, louder, quieter }

    /// The virtual key codes the monitor reads. Carbon's names, without Carbon.
    static let escape: UInt16 = 53
    static let enter: UInt16 = 36
    static let keypadEnter: UInt16 = 76
    static let space: UInt16 = 49
    static let up: UInt16 = 126
    static let down: UInt16 = 125

    /// The flags a listener holds. An arrow key's own event carries `.function` and
    /// `.numericPad` with nothing held at all, so those two are not modifiers here.
    private static let held: NSEvent.ModifierFlags = [.shift, .control, .option, .command]

    static func action(keyCode: UInt16, modifiers: NSEvent.ModifierFlags) -> Action? {
        switch (keyCode, modifiers.intersection(held)) {
        case (escape, []): return .dismiss
        case (enter, []), (keypadEnter, []), (space, []): return .play
        case (up, []): return .louder
        case (down, []): return .quieter
        case (up, .option): return .faster
        case (down, .option): return .slower
        default: return nil
        }
    }
}
