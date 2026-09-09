import SwiftUI

/// Click cycles to the next step, the menu picks any step.
public struct RateButton: View {
    let label: String
    let all: [String]
    let onCycle: () -> Void
    let onPick: (Int) -> Void
    public init(
        label: String, all: [String], onCycle: @escaping () -> Void,
        onPick: @escaping (Int) -> Void
    ) {
        self.label = label
        self.all = all
        self.onCycle = onCycle
        self.onPick = onPick
    }
    public var body: some View {
        Button(label, action: onCycle)
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
