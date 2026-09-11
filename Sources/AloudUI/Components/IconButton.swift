import SwiftUI

/// A symbol-only button for toolbars. It carries no glass of its own: a macOS 26
/// toolbar already draws its items in glass, and a second layer nests a capsule
/// inside the toolbar's capsule.
public struct IconButton: View {
    let symbol: String
    let label: String
    let action: () -> Void
    public init(_ symbol: String, label: String, action: @escaping () -> Void) {
        self.symbol = symbol
        self.label = label
        self.action = action
    }
    public var body: some View {
        Button(action: action) {
            Image(systemName: symbol)
                // A control's square, so the glyph has the same room on every side as
                // its neighbours and the press lands anywhere in it.
                .frame(width: Size.control, height: Size.control)
                .contentShape(.rect)
        }
        .buttonStyle(.borderless)
        .accessibilityLabel(label)
        .help(label)
    }
}
