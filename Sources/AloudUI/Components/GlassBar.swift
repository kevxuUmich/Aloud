import SwiftUI

/// A Liquid Glass bar. It is the pad and the material and nothing else: what lays out
/// inside it is the caller's, a row or a stack of rows.
///
/// `docked` is the bar that sits on the window's bottom edge: it rounds its two top
/// corners and squares the two at the bottom, because the window's own corner is
/// already there and a second one inside it reads as a gap.
public struct GlassBar<Content: View>: View {
    let docked: Bool
    let content: Content
    public init(docked: Bool = false, @ViewBuilder content: () -> Content) {
        self.docked = docked
        self.content = content()
    }
    public var body: some View {
        content
            .padding(.horizontal, Space.xl)
            .padding(.vertical, Space.m)
            .glassEffect(.regular, in: shape)
    }
    var shape: UnevenRoundedRectangle {
        docked
            ? UnevenRoundedRectangle(
                topLeadingRadius: Radius.dockedTop, bottomLeadingRadius: Radius.none,
                bottomTrailingRadius: Radius.none, topTrailingRadius: Radius.dockedTop)
            : UnevenRoundedRectangle(
                topLeadingRadius: Radius.l, bottomLeadingRadius: Radius.l,
                bottomTrailingRadius: Radius.l, topTrailingRadius: Radius.l)
    }
}
