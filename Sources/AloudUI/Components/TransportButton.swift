import SwiftUI

public struct TransportButton: View {
    public enum Kind { case back, play, pause, forward }
    /// The skip interval as the titles say it. `AloudUI` cannot see `Player.skipSeconds`,
    /// so the app passes it in and the button's words cannot drift from the step it
    /// actually takes, and the glyph carries the same number.
    public static let defaultSkipSeconds = 10
    let kind: Kind
    let skipSeconds: Int
    let action: () -> Void
    public init(
        _ kind: Kind, skipSeconds: Int = TransportButton.defaultSkipSeconds,
        action: @escaping () -> Void
    ) {
        self.kind = kind
        self.skipSeconds = skipSeconds
        self.action = action
    }
    var symbol: String {
        switch kind {
        case .back: "\(skipSeconds).arrow.trianglehead.counterclockwise"
        case .play: "play.fill"
        case .pause: "pause.fill"
        case .forward: "\(skipSeconds).arrow.trianglehead.clockwise"
        }
    }
    var label: String {
        switch kind {
        case .back: "Back \(skipSeconds) seconds"
        case .play: "Play"
        case .pause: "Pause"
        case .forward: "Forward \(skipSeconds) seconds"
        }
    }
    var size: CGFloat { kind == .play || kind == .pause ? Size.playControl : Size.control }
    public var body: some View {
        Button(action: action) {
            Image(systemName: symbol)
                .resizable().scaledToFit()
                .frame(width: size, height: size)
                .padding(Space.xs)
        }
        .buttonStyle(.plain)
        .accessibilityLabel(label)
        .help(label)
    }
}
