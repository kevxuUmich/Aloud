import Foundation
import Prose
import Vault

/// The one line under a card in the library: what the reader has done with this
/// document, or what it would cost to read it. It is a rule about text and timing,
/// so it lives here and not in a view.
public enum DocumentStatus {
    /// `remaining` is the player's, and is read only when this document is the one
    /// loaded; anything else is a clock counting down a document nobody is on.
    public static func label(
        progress: PlaybackProgress?, isCurrent: Bool, remaining: Duration?, previewWords: Int,
        bytes: Int, rateFactor: Double
    ) -> String {
        if let p = progress {
            if p.finished { return "Finished" }
            if p.sentenceIndex > 0 {
                if isCurrent, let remaining { return Format.clock(remaining) + " left" }
                return "In progress"
            }
        }
        // Only the first bytes of a file are read at scan time, so a file longer than
        // its preview is estimated from its size at one word per six bytes.
        let words = max(previewWords, bytes / bytesPerWord)
        guard words > 0 else { return "" }
        return "~" + Format.minutes(Estimate.duration(words: words, factor: rateFactor))
    }

    static let bytesPerWord = 6
}
