import SwiftUI

/// Elapsed and remaining labels around a seekable track. `progress` is 0...1.
public struct Scrubber: View {
    let progress: Double
    let elapsed: String
    let remaining: String
    let onSeek: (Double) -> Void
    public init(
        progress: Double, elapsed: String, remaining: String, onSeek: @escaping (Double) -> Void
    ) {
        self.progress = progress
        self.elapsed = elapsed
        self.remaining = remaining
        self.onSeek = onSeek
    }
    public var body: some View {
        HStack(spacing: Space.m) {
            Text(elapsed).font(Type.caption).foregroundStyle(Ink.soft).monospacedDigit()
            GeometryReader { geo in
                ZStack(alignment: .leading) {
                    Capsule().fill(Ink.track)
                    Capsule().fill(Ink.primary).frame(width: geo.size.width * progress)
                }
                .contentShape(Rectangle())
                .gesture(
                    DragGesture(minimumDistance: 0).onEnded { v in
                        onSeek(min(max(v.location.x / geo.size.width, 0), 1))
                    })
            }
            .frame(height: Size.scrubberTrack)
            Text(remaining).font(Type.caption).foregroundStyle(Ink.soft).monospacedDigit()
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel("Position \(elapsed), \(remaining) remaining")
    }
}
