import AloudUI
import AppKit
import Speech
import SwiftUI

/// The clipboard card bound to the model: the strings come from the panel's state,
/// and the transport drives the one player once the note is playing.
struct ClipboardPanelView: View {
    var model: AppModel
    /// Where the card's Play is handed up to the controller, so a key press does
    /// exactly what a click does, `openWindow` included, which only a view in the
    /// hierarchy can reach.
    let actions: PanelActions
    @Environment(\.openWindow) private var openWindow
    var player: Player { model.player }

    var body: some View {
        // Nil draws an empty card for the instant between dismiss and order-out; the
        // controller never leaves the panel up over it.
        let state = model.clipboardPanel ?? .empty
        card(for: state)
            .onChange(of: model.clipboardPanel, initial: true) { _, now in
                actions.play = { if let now { play(now) } }
            }
    }

    /// The focus ring is off: the panel is made key so Enter, Space and Escape reach
    /// it, and without this the first transport button would wear a ring every time
    /// the panel opens.
    func card(for state: ClipboardPanelState) -> some View {
        ClipboardCard(
            title: title(for: state), subtitle: subtitle(for: state), transport: transport(for: state),
            progress: isPlayer(state) ? player.progress : 0,
            elapsed: Format.clock(isPlayer(state) ? player.elapsed : .zero),
            remaining: "~" + Format.clock(remaining(for: state)),
            skipSeconds: AloudApp.skipStep,
            onPlay: { play(state) },
            onBack: { player.skip(seconds: -Player.skipSeconds) },
            onForward: { player.skip(seconds: Player.skipSeconds) },
            onSeek: { player.seek(progress: $0) }
        )
        .focusEffectDisabled()
    }

    func isPlayer(_ s: ClipboardPanelState) -> Bool {
        if case .playing = s { return true }
        return false
    }

    func title(for s: ClipboardPanelState) -> String {
        s.preview?.title ?? "Nothing to read"
    }

    func subtitle(for s: ClipboardPanelState) -> String {
        switch s {
        case .empty: "The clipboard has no text"
        case .needsFolder: "Pick a folder in Aloud first"
        case .preview(_, let failure?): failure
        case .preview(let p, nil), .playing(let p):
            "\(p.source.label) · \(player.rate.label) · ~\(Format.minutes(p.estimate(factor: player.rate.factor))) · \(p.words) words"
        }
    }

    func transport(for s: ClipboardPanelState) -> ClipboardCard.Transport {
        switch s {
        case .empty: .disabled
        case .preview, .needsFolder: .ready
        case .playing: .playing(isPlaying: player.isPlaying)
        }
    }

    func remaining(for s: ClipboardPanelState) -> Duration {
        switch s {
        case .playing: player.remaining
        case .empty: .zero
        case .preview(let p, _), .needsFolder(let p): p.estimate(factor: player.rate.factor)
        }
    }

    /// Play before the note exists writes it; after, it is the player's toggle. With
    /// no folder it opens the window, where one can be picked.
    func play(_ s: ClipboardPanelState) {
        switch s {
        case .empty: break
        case .preview: model.playPreview()
        case .playing: player.toggle()
        case .needsFolder:
            model.dismissClipboardPanel()
            openWindow(id: AloudApp.mainWindowID)
            NSApp.activate()
        }
    }
}
