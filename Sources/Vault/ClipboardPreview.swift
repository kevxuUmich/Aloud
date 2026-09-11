import Foundation
import Prose

/// The clipboard as a note would take it, before it is a file: what the panel shows
/// and what `Vault.makeNote` will write if Play is pressed. Title, words and the
/// estimate are the library's own rules, so the panel can never disagree with the
/// card the note gets once it is written.
public struct ClipboardPreview: Equatable, Sendable {
    public let text: String
    public let title: String
    public let words: Int

    /// Nil when there is nothing there once the whitespace is trimmed, which is what
    /// the hotkey has to know first.
    public init?(text: String) {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }
        self.text = trimmed
        // The fallback is the file's own fallback: `NoteName.make` names an untitled
        // note "Note", so the panel says the same.
        let t = Title.from(text: trimmed, fallback: "Note")
        self.title = t.isEmpty ? "Note" : t
        self.words = Estimate.words(in: trimmed)
    }

    public func estimate(factor: Double) -> Duration {
        Estimate.duration(words: words, factor: factor)
    }
}
