import SwiftUI

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
                .frame(width: Size.control, height: Size.control)
        }
        .buttonStyle(.glass)
        .accessibilityLabel(label)
        .help(label)
    }
}
