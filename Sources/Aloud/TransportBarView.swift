import AloudUI
import Speech
import SwiftUI

struct TransportBarView: View {
    var model: AppModel
    var player: Player { model.player }
    @State private var showVoices = false

    /// Nothing loaded: the bar is still there, docked and the width of the window, but
    /// every control in it is disabled and the title slot says so. The scrubber reads
    /// 0:00 and ~0:00 on its own, since an empty timeline is zero long.
    var isLoaded: Bool { model.current != nil }

    var body: some View {
        GlassBar(docked: true) {
            VStack(spacing: Space.s) {
                Scrubber(
                    progress: player.progress,
                    elapsed: Format.clock(player.elapsed),
                    remaining: "~" + Format.clock(player.remaining),
                    onSeek: { player.seek(progress: $0) }
                )
                .disabled(!isLoaded)
                HStack {
                    Group {
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
                    }
                    .disabled(!isLoaded)
                    title
                }
            }
        }
    }

    /// The title slot: what is loaded, or that nothing is. On the reader the title is
    /// already on screen above the bar, so the slot is empty there.
    @ViewBuilder var title: some View {
        if let c = model.current {
            if case .reader? = model.path.last {
                EmptyView()
            } else {
                Button(c.title) { model.open(c) }
                    .font(Type.caption).buttonStyle(.plain).lineLimit(1)
            }
        } else {
            Text("Nothing loaded").font(Type.caption).foregroundStyle(Ink.soft)
        }
    }
}
