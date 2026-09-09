import AloudUI
import Speech
import SwiftUI

struct TransportBarView: View {
    var model: AppModel
    var player: Player { model.player }

    var body: some View {
        VStack(spacing: Space.s) {
            Scrubber(
                progress: player.progress,
                elapsed: Format.clock(player.elapsed),
                remaining: "~" + Format.clock(player.remaining),
                onSeek: { player.seek(progress: $0) })
            HStack {
                RateButton(
                    label: player.rate.label, all: Rate.allCases.map(\.label),
                    onCycle: { player.rate = player.rate.next },
                    onPick: { player.rate = Rate.allCases[$0] })
                Spacer()
                HStack(spacing: Space.xl) {
                    TransportButton(.back15) { player.skip(seconds: -Player.skipSeconds) }
                    TransportButton(player.isPlaying ? .pause : .play) { player.toggle() }
                    TransportButton(.forward15) { player.skip(seconds: Player.skipSeconds) }
                }
                Spacer()
                if model.current != nil, case .reader? = model.path.last {
                    // On the reader, the title is already on screen; show nothing here.
                } else if let c = model.current {
                    Button(c.title) { model.open(c) }.font(Type.caption).buttonStyle(.plain).lineLimit(1)
                }
            }
        }
        .padding(.horizontal, Space.xl)
        .padding(.vertical, Space.m)
        .glassEffect(.regular, in: .rect(cornerRadius: Radius.l))
    }
}
