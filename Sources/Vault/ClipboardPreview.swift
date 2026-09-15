import Foundation
import Prose

/// Text as a note would take it, before it is a file: what the panel shows and what
/// `Vault.makeNote` will write if Play is pressed. Title, words and the estimate are
/// the library's own rules, so the panel can never disagree with the card the note
/// gets once it is written. From the clipboard or the selection in the app in front;
/// the name is from the days it was only the clipboard.
public struct ClipboardPreview: Equatable, Sendable {
    /// Where the hotkey found the text. The card's second line and the note's Now
    /// Playing subtitle say it.
    public enum Source: Sendable {
        case selection, clipboard

        public var label: String {
            switch self {
            case .selection: "From selection"
            case .clipboard: "From clipboard"
            }
        }
    }

    public let text: String
    public let title: String
    public let words: Int
    public let source: Source
    /// The app the text was found in, and the page when it was one. Nil when the
    /// hotkey could not tell, in which case `source` alone is what the card says.
    public let origin: Origin?

    /// The card's second line begins with this, and the note's Now Playing subtitle
    /// is it: the app by name when it is known, else which way the text came in.
    public var label: String { origin?.label ?? source.label }

    /// Nil when there is nothing there once the whitespace is trimmed, which is what
    /// the hotkey has to know first.
    public init?(text: String, source: Source = .clipboard, origin: Origin? = nil) {
        self.source = source
        self.origin = origin
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
