import AloudUI
import Speech
import SwiftUI

struct TransportBarView: View {
    var model: AppModel
    var player: Player { model.player }
    @State private var showVoices = false

    /// Nothing loaded: the bar is still there, docked and the width of the window, but
    /// the scrubber and the transport controls are disabled and the title slot says so.
    /// The scrubber reads 0:00 and ~0:00 on its own, since an empty timeline is zero
    /// long. The voice button is the exception, and stays live.
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
                // Three columns: the title at the left, the transport at the true
                // centre, the speed and the voice at the right. The side columns are
                // both flexible and equal, so the centre stays centred however long the
                // title is; a single row with spacers put the cluster wherever the two
                // sides happened to balance.
                HStack(spacing: Space.m) {
                    title
                        .frame(maxWidth: .infinity, alignment: .leading)
                    HStack(spacing: Space.xl) {
                        TransportButton(.back15, skipSeconds: AloudApp.skipStep) {
                            player.skip(seconds: -Player.skipSeconds)
                        }
                        TransportButton(player.isPlaying ? .pause : .play) { player.toggle() }
                        TransportButton(.forward15, skipSeconds: AloudApp.skipStep) {
                            player.skip(seconds: Player.skipSeconds)
                        }
                    }
                    .fixedSize()
                    .disabled(!isLoaded)
                    HStack(spacing: Space.m) {
                        RateButton(
                            label: player.rate.label, all: Rate.allCases.map(\.label),
                            onCycle: { model.setRate(player.rate.next) },
                            onPick: { model.setRate(Rate.allCases[$0]) }
                        )
                        .disabled(!isLoaded)
                        // Outside the disabled set on purpose: a listener may want to
                        // hear the voices and choose one before opening anything at all.
                        IconButton("person.wave.2", label: "Voice") { showVoices.toggle() }
                            .help(player.voice?.name ?? "Voice")
                            .popover(isPresented: $showVoices, arrowEdge: .top) {
                                VoicePopover(model: model)
                            }
                    }
                    .frame(maxWidth: .infinity, alignment: .trailing)
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
                    .font(Type.caption).buttonStyle(.plain).lineLimit(Type.singleLine)
            }
        } else {
            Text("Nothing loaded").font(Type.caption).foregroundStyle(Ink.soft)
        }
    }
}
