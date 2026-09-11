import KeyboardShortcuts

extension KeyboardShortcuts.Name {
    /// The system-wide shortcut, Option+Space by default: whatever text is on the
    /// clipboard becomes a note and starts reading, whichever app is in front.
    ///
    /// `@MainActor` because `Name` is not `Sendable` in the pinned version, and the one
    /// place this is read is `AppModel.installHotkey`, which is on the main actor.
    @MainActor
    static let pasteAndPlay = Self(
        "pasteAndPlay", default: .init(.space, modifiers: [.option]))
}
