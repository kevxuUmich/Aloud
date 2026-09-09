import SwiftUI

/// A Liquid Glass bar; content lays out horizontally inside it.
public struct GlassBar<Content: View>: View {
    let content: Content
    public init(@ViewBuilder content: () -> Content) { self.content = content() }
    public var body: some View {
        HStack(spacing: Space.l) { content }
            .padding(.horizontal, Space.xl)
            .padding(.vertical, Space.m)
            .glassEffect(.regular, in: .rect(cornerRadius: Radius.l))
    }
}
