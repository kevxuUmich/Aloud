import SwiftUI

/// The aperture: Aloud's mark. A ring on the superellipse shape law, turned so a flat
/// side faces the lower-right diagonal, and open there. It is drawn from four numbers
/// in `Mark` rather than loaded from a picture, so it is the same at every size and
/// takes whatever colour it is given.
///
/// The path is the ring's centreline; `ApertureGlyph` strokes it at the mark's own
/// weight. In the ring's own frame a point at polar angle `phi` sits at
/// `r = a / (|cos phi|^n + |sin phi|^n)^(1/n)`, and the opening is the run of angles
/// within `Mark.gapHalfAngle` of the flat side on the positive x axis, which the turn
/// then carries to the lower right.
public struct ApertureMark: Shape {
    public init() {}

    public func path(in rect: CGRect) -> Path {
        let side = min(rect.width, rect.height)
        let a = side * Mark.body / 2
        let centre = CGPoint(x: rect.midX, y: rect.midY)
        let n = Mark.exponent
        let gap = Mark.gapHalfAngle * .pi / 180
        let turn = Mark.turnDegrees * .pi / 180
        let span = 2 * .pi - 2 * gap
        var path = Path()
        for i in 0...Mark.samples {
            let phi = gap + span * CGFloat(i) / CGFloat(Mark.samples)
            let c = cos(phi)
            let s = sin(phi)
            let r = a / pow(pow(abs(c), n) + pow(abs(s), n), 1 / n)
            let theta = phi + turn
            let p = CGPoint(x: centre.x + r * cos(theta), y: centre.y + r * sin(theta))
            if i == 0 { path.move(to: p) } else { path.addLine(to: p) }
        }
        return path
    }
}

/// The mark drawn at its own weight, square, in the current foreground style.
public struct ApertureGlyph: View {
    public init() {}
    public var body: some View {
        GeometryReader { geo in
            let side = min(geo.size.width, geo.size.height)
            ApertureMark()
                .stroke(style: StrokeStyle(lineWidth: side * Mark.stroke, lineCap: .round))
                .frame(width: side, height: side)
        }
        .aspectRatio(1, contentMode: .fit)
    }
}
