import SwiftUI

public struct Notice: View {
    let text: String
    public init(_ text: String) { self.text = text }
    public var body: some View {
        Label(text, systemImage: "exclamationmark.triangle")
            .font(Type.caption)
            .padding(.horizontal, Space.m).padding(.vertical, Space.s)
            .glassEffect(.regular, in: .capsule)
    }
}
