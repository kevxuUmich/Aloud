import SwiftUI

/// The clipboard panel's drawing, laid out like the system's Now Playing card: a
/// square glyph plate at the left, the title and a subtitle at the right, the
/// transport under them and the scrubber under that. It knows nothing about the
/// player; the app hands it strings and closures, so the gallery can show every state.
public struct ClipboardCard: View {
    public enum Transport: Equatable {
        /// Nothing to play: the empty clipboard, or no folder to write into.
        case disabled
        /// Before Play: Play alone is live and the scrubber is empty.
        case ready
        /// After Play: the mini player, bound to the one player.
        case playing(isPlaying: Bool)
    }
    let title: String
    let subtitle: String
    let transport: Transport
    let progress: Double
    let elapsed: String
    let remaining: String
    let skipSeconds: Int
    let onPlay: () -> Void
    let onBack: () -> Void
    let onForward: () -> Void
    let onSeek: (Double) -> Void

    public init(
        title: String, subtitle: String, transport: Transport,
        progress: Double, elapsed: String, remaining: String,
        skipSeconds: Int = TransportButton.defaultSkipSeconds,
        onPlay: @escaping () -> Void, onBack: @escaping () -> Void, onForward: @escaping () -> Void,
        onSeek: @escaping (Double) -> Void
    ) {
        self.title = title
        self.subtitle = subtitle
        self.transport = transport
        self.progress = progress
        self.elapsed = elapsed
        self.remaining = remaining
        self.skipSeconds = skipSeconds
        self.onPlay = onPlay
        self.onBack = onBack
        self.onForward = onForward
        self.onSeek = onSeek
    }

    var isPlayer: Bool {
        if case .playing = transport { return true }
        return false
    }
    var showsPause: Bool {
        if case .playing(let isPlaying) = transport { return isPlaying }
        return false
    }

    public var body: some View {
        GlassBar {
            VStack(spacing: Space.m) {
                HStack(alignment: .top, spacing: Space.l) {
                    plate
                    VStack(alignment: .leading, spacing: Space.xs) {
                        Text(title).font(Type.panelTitle).lineLimit(Type.cardTitleLines)
                        Text(subtitle).font(Type.panelSubtitle).foregroundStyle(Ink.soft)
                            .lineLimit(Type.singleLine)
                        Spacer(minLength: Space.none)
                        HStack(spacing: Space.xl) {
                            TransportButton(.back15, skipSeconds: skipSeconds, action: onBack)
                                .disabled(!isPlayer)
                            TransportButton(showsPause ? .pause : .play, action: onPlay)
                                .disabled(transport == .disabled)
                            TransportButton(.forward15, skipSeconds: skipSeconds, action: onForward)
                                .disabled(!isPlayer)
                        }
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                }
                Scrubber(progress: progress, elapsed: elapsed, remaining: remaining, onSeek: onSeek)
                    .disabled(!isPlayer)
            }
        }
        .frame(width: Size.clipboardPanelWidth)
    }

    var plate: some View {
        RoundedRectangle(cornerRadius: Radius.plate, style: .continuous)
            .fill(Ink.plate)
            .frame(width: Size.clipboardPlate, height: Size.clipboardPlate)
            .overlay {
                Image(systemName: "waveform")
                    .resizable().scaledToFit()
                    .frame(width: Size.clipboardGlyph, height: Size.clipboardGlyph)
                    .foregroundStyle(Ink.plateGlyph)
            }
            .accessibilityHidden(true)
    }
}
