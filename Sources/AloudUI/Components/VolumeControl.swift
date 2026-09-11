import SwiftUI

/// The player's level: a speaker whose glyph follows the level, and a short slider.
/// `onCommit` fires when the drag ends, so a level is applied once per gesture rather
/// than on every tick, since applying one mid-sentence re-speaks the sentence's rest.
public struct VolumeControl: View {
    @Binding var volume: Double
    let onCommit: () -> Void
    public init(volume: Binding<Double>, onCommit: @escaping () -> Void) {
        _volume = volume
        self.onCommit = onCommit
    }
    var symbol: String {
        switch volume {
        case 0: "speaker.slash.fill"
        case ..<Level.low: "speaker.wave.1.fill"
        case ..<Level.high: "speaker.wave.2.fill"
        default: "speaker.wave.3.fill"
        }
    }
    public var body: some View {
        HStack(spacing: Space.s) {
            Image(systemName: symbol)
                .frame(width: Size.icon, height: Size.icon)
                .foregroundStyle(Ink.soft)
                .accessibilityHidden(true)
            Slider(value: $volume, in: 0...1) {
                Text("Volume")
            } onEditingChanged: { editing in
                if !editing { onCommit() }
            }
            .labelsHidden()
            .frame(width: Size.volumeSlider)
            .controlSize(.small)
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel("Volume \(Int((volume * Level.percent).rounded())) percent")
        .help("Volume")
    }
    /// Where the speaker's waves step up.
    enum Level {
        static let low = 1.0 / 3.0
        static let high = 2.0 / 3.0
        static let percent = 100.0
    }
}
