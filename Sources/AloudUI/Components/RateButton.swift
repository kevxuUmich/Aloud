import SwiftUI

/// Click opens the pace sliders, the menu picks any step.
public struct RateButton: View {
    let label: String
    let all: [String]
    let onOpen: () -> Void
    let onPick: (Int) -> Void
    public init(
        label: String, all: [String], onOpen: @escaping () -> Void,
        onPick: @escaping (Int) -> Void
    ) {
        self.label = label
        self.all = all
        self.onOpen = onOpen
        self.onPick = onPick
    }
    public var body: some View {
        // Every step's label laid under the current one, hidden, so the button is as
        // wide as the widest of them at every speed and the row does not shift as the
        // speed changes.
        Button(action: onOpen) {
            ZStack {
                ForEach(all, id: \.self) { Text($0).hidden() }
                Text(label)
            }
            .monospacedDigit()
        }
        .font(Type.control)
        .buttonStyle(.glass)
        .contextMenu {
            ForEach(Array(all.enumerated()), id: \.offset) { i, s in
                Button(s) { onPick(i) }
            }
        }
        .accessibilityLabel("Speed \(label)")
    }
}
