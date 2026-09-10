import SwiftUI
import Testing

@testable import AloudUI

@Suite struct ApertureMarkTests {
    let frame = CGRect(x: 0, y: 0, width: 96, height: 96)

    /// Every point the path visits, in order.
    func points(_ path: Path) -> [CGPoint] {
        var out: [CGPoint] = []
        path.forEach { element in
            switch element {
            case .move(let p), .line(let p): out.append(p)
            default: break
            }
        }
        return out
    }

    @Test func fitsInsideItsFrameWithTheStroke() {
        let path = ApertureMark().path(in: frame)
        let inset = frame.insetBy(dx: Mark.stroke * frame.width / 2, dy: Mark.stroke * frame.height / 2)
        #expect(inset.contains(path.boundingRect))
        #expect(path.boundingRect.width > frame.width / 2)
    }

    /// The opening is centred on the lower-right diagonal: the two ends mirror each
    /// other across it, and both sit in that quadrant.
    @Test func opensAtTheLowerRightSymmetrically() throws {
        let pts = points(ApertureMark().path(in: frame))
        let first = try #require(pts.first)
        let last = try #require(pts.last)
        #expect(abs(first.x - last.y) < 0.01)
        #expect(abs(first.y - last.x) < 0.01)
        #expect(first.x > frame.midX && first.y > frame.midY)
        #expect(last.x > frame.midX && last.y > frame.midY)
    }

    /// Nothing is drawn across the opening: the point where a closed ring would cross
    /// the diagonal is well clear of every point the path visits.
    @Test func leavesTheDiagonalClear() {
        let pts = points(ApertureMark().path(in: frame))
        let a = Mark.body * frame.width / 2
        let onDiagonal = CGPoint(x: frame.midX + a * cos(.pi / 4), y: frame.midY + a * sin(.pi / 4))
        let nearest = pts.map { hypot($0.x - onDiagonal.x, $0.y - onDiagonal.y) }.min() ?? 0
        // The round caps reach half a stroke past the ends, and must not reach the diagonal.
        #expect(nearest > Mark.stroke * frame.width / 2)
    }

    /// The SVG's own end points, in its 96-point frame.
    @Test func matchesTheDrawing() throws {
        let pts = points(ApertureMark().path(in: frame))
        let first = try #require(pts.first)
        #expect(abs(first.x - 66.12) < 0.1)
        #expect(abs(first.y - 77.65) < 0.1)
    }
}
