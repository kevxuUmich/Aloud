import SwiftUI

/// A Liquid Glass bar. It is the pad and the material and nothing else: what lays out
/// inside it is the caller's, a row or a stack of rows.
public struct GlassBar<Content: View>: View {
    let content: Content
    public init(@ViewBuilder content: () -> Content) { self.content = content() }
    public var body: some View {
        content
            .padding(.horizontal, Space.xl)
            .padding(.vertical, Space.m)
            .glassEffect(.regular, in: .rect(cornerRadius: Radius.l))
    }
}
