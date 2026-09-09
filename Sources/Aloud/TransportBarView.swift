import AloudUI
import Speech
import SwiftUI

struct TransportBarView: View {
    var model: AppModel
    var player: Player { model.player }
    @State private var showVoices = false

    var body: some View {
        GlassBar {
            VStack(spacing: Space.s) {
                Scrubber(
                    progress: player.progress,
                    elapsed: Format.clock(player.elapsed),
                    remaining: "~" + Format.clock(player.remaining),
                    onSeek: { player.seek(progress: $0) })
                HStack {
                    RateButton(
                        label: player.rate.label, all: Rate.allCases.map(\.label),
                        onCycle: { model.setRate(player.rate.next) },
                        onPick: { model.setRate(Rate.allCases[$0]) })
                    Spacer()
                    HStack(spacing: Space.xl) {
                        TransportButton(.back15, skipSeconds: AloudApp.skipStep) {
                            player.skip(seconds: -Player.skipSeconds)
                        }
                        TransportButton(player.isPlaying ? .pause : .play) { player.toggle() }
                        TransportButton(.forward15, skipSeconds: AloudApp.skipStep) {
                            player.skip(seconds: Player.skipSeconds)
                        }
                    }
                    Spacer()
                    IconButton("person.wave.2", label: "Voice") { showVoices.toggle() }
                        .help(player.voice?.name ?? "Voice")
                        .popover(isPresented: $showVoices, arrowEdge: .top) {
                            VoicePopover(model: model)
                        }
                    if model.current != nil, case .reader? = model.path.last {
                        // On the reader, the title is already on screen; show nothing here.
                    } else if let c = model.current {
                        Button(c.title) { model.open(c) }.font(Type.caption).buttonStyle(.plain).lineLimit(1)
                    }
                }
            }
        }
    }
}
