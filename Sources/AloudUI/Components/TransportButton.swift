import SwiftUI

public struct TransportButton: View {
    public enum Kind { case back15, play, pause, forward15 }
    let kind: Kind
    let action: () -> Void
    public init(_ kind: Kind, action: @escaping () -> Void) {
        self.kind = kind
        self.action = action
    }
    var symbol: String {
        switch kind {
        case .back15: "15.arrow.trianglehead.counterclockwise"
        case .play: "play.fill"
        case .pause: "pause.fill"
        case .forward15: "15.arrow.trianglehead.clockwise"
        }
    }
    var label: String {
        switch kind {
        case .back15: "Back 15 seconds"
        case .play: "Play"
        case .pause: "Pause"
        case .forward15: "Forward 15 seconds"
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
