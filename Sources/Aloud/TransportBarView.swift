import AloudUI
import Speech
import SwiftUI
import Vault

struct TransportBarView: View {
    var model: AppModel
    var player: Player { model.player }
    @State private var showVoices = false
    @State private var showPace = false
    /// The slider's own copy of the level while it is dragged. The player hears the
    /// change on release, since applying it mid-sentence re-speaks the sentence's rest,
    /// and a drag that did that on every tick would stutter.
    @State private var draggedVolume: Double?
    /// True while the pointer is over the title slot, which is when the file's picture
    /// gives way to the X that unloads it.
    @State private var hoveringTitle = false

    /// The bar is shown only while something is loaded, so this is true whenever
    /// the bar is on screen; the controls it gates are kept gated so a bar caught
    /// mid-transition after an unload cannot be pressed on an empty player.
    var isLoaded: Bool { model.current != nil }

    var body: some View {
        GlassBar {
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
                        TransportButton(.back, skipSeconds: AloudApp.skipStep) {
                            player.skip(seconds: -Player.skipSeconds)
                        }
                        TransportButton(player.isPlaying ? .pause : .play) { player.toggle() }
                        TransportButton(.forward, skipSeconds: AloudApp.skipStep) {
                            player.skip(seconds: Player.skipSeconds)
                        }
                    }
                    .fixedSize()
                    .disabled(!isLoaded)
                    HStack(spacing: Space.m) {
                        // Live like the voice button: a level can be set before
                        // anything is loaded and is kept for whatever is.
                        VolumeControl(
                            volume: Binding(
                                get: { draggedVolume ?? player.volume },
                                set: { draggedVolume = $0 }),
                            onCommit: {
                                if let v = draggedVolume { model.setVolume(v) }
                                draggedVolume = nil
                            })
                        // The speed opens the pace sliders: speed itself and the two
                        // pauses. Live like the voice button, since a pace can be set
                        // before anything is loaded and is kept for whatever is.
                        RateButton(
                            label: player.rate.label, all: Rate.allCases.map(\.label),
                            onOpen: { showPace.toggle() },
                            onPick: { model.setRate(Rate.allCases[$0]) }
                        )
                        .help("Speed and pauses")
                        .popover(isPresented: $showPace, arrowEdge: .top) {
                            PacePopover(model: model)
                        }
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

    /// The title slot: what is loaded, or that nothing is. It shows on the reader too,
    /// under the title in the toolbar: the bar looks the same on every page, and
    /// pressing it there is a no-op apart from `open`'s check that the file has not
    /// changed underneath.
    ///
    /// Beside the title is the file's own picture, the card's thumbnail shrunk to the
    /// row, or for a note the panel wrote, the icon of the app the text came from.
    /// Under the pointer the picture becomes an X, and pressing it unloads the
    /// file: the player stops, the slot reads "Nothing loaded", and a reader standing
    /// in the file goes back to the library. The hover is the whole slot, picture and
    /// title, so the X is found by whoever reaches for either; only the picture itself
    /// is the button, so a press on the title still opens the file.
    @ViewBuilder var title: some View {
        if let c = model.current {
            HStack(spacing: Space.s) {
                Button {
                    model.unload()
                } label: {
                    ZStack {
                        picture(of: c)
                            .opacity(hoveringTitle ? 0 : 1)
                        Image(systemName: "xmark.circle.fill")
                            .font(Type.control)
                            .foregroundStyle(Ink.soft)
                            .opacity(hoveringTitle ? 1 : 0)
                    }
                    .contentShape(.rect)
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Stop and unload \(c.title)")
                .help("Stop and unload")
                Button(c.title) { model.open(c) }
                    .font(Type.caption).buttonStyle(.plain).lineLimit(Type.singleLine)
            }
            .onHover { hoveringTitle = $0 }
            .animation(Motion.quick, value: hoveringTitle)
        } else {
            Text("Nothing loaded").font(Type.caption).foregroundStyle(Ink.soft)
        }
    }

    @ViewBuilder func picture(of doc: Document) -> some View {
        if let icon = OriginIcon.image(for: doc.origin) {
            Image(nsImage: icon)
                .resizable()
                .interpolation(.high)
                .frame(width: Size.barIcon, height: Size.barIcon)
                .accessibilityHidden(true)
        } else {
            Thumb(preview: doc.preview, scale: .bar)
        }
    }
}
