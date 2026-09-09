import Vault

/// What the clipboard panel is showing. Nil on the model means no panel.
enum ClipboardPanelState: Equatable {
    /// The clipboard has no text. The panel says so and goes away by itself.
    case empty
    /// The text, before Play. `failure` is a write that did not land, shown in the
    /// subtitle's place so Play can be tried again.
    case preview(ClipboardPreview, failure: String? = nil)
    /// The text, but nowhere to write it. Play opens the window instead.
    case needsFolder(ClipboardPreview)
    /// The note is written and the panel is a mini player for it.
    case playing(ClipboardPreview)

    var preview: ClipboardPreview? {
        switch self {
        case .empty: nil
        case .preview(let p, _), .needsFolder(let p), .playing(let p): p
        }
    }
}
