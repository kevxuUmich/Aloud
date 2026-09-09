import AloudUI
import AppKit
import Speech
import SwiftUI

/// The menu bar's player: the same `AppModel`, so what it shows and what it does are
/// the window's own player rather than a second one.
struct MenuBarPanel: View {
    var model: AppModel
    @Environment(\.openWindow) private var openWindow
    var player: Player { model.player }

    var body: some View {
        VStack(alignment: .leading, spacing: Space.m) {
            Text(model.current?.title ?? "Nothing loaded").font(Type.cardTitle).lineLimit(1)
            Text(
                model.currentSentenceText
                    ?? "Pick a document in Aloud, or press the hotkey with text on the clipboard."
            )
            .font(Type.caption).foregroundStyle(Ink.soft).lineLimit(Type.panelSentenceLines)
            HStack(spacing: Space.l) {
                TransportButton(.back15, skipSeconds: AloudApp.skipStep) {
                    player.skip(seconds: -Player.skipSeconds)
                }
                TransportButton(player.isPlaying ? .pause : .play) { player.toggle() }
                TransportButton(.forward15, skipSeconds: AloudApp.skipStep) {
                    player.skip(seconds: Player.skipSeconds)
                }
                Spacer()
                RateButton(
                    label: player.rate.label, all: Rate.allCases.map(\.label),
                    onCycle: { model.setRate(player.rate.next) },
                    onPick: { model.setRate(Rate.allCases[$0]) })
            }
            .disabled(model.current == nil)
            Divider()
            Button("Open Aloud") {
                openWindow(id: AloudApp.mainWindowID)
                NSApp.activate()
            }
            Button("Quit Aloud") { NSApp.terminate(nil) }
        }
        .padding(Space.l)
        .frame(width: Size.panelWidth)
    }
}
