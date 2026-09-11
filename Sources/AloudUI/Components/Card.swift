import SwiftUI

public struct Card: View {
    public let title: String
    public let preview: String
    public let status: String
    public init(title: String, preview: String, status: String) {
        self.title = title
        self.preview = preview
        self.status = status
    }
    public var body: some View {
        VStack(spacing: Space.s) {
            // The label below carries the picture's words for a reader.
            Thumb(preview: preview, scale: .card)
            Text(title)
                .font(Type.cardTitle)
                .multilineTextAlignment(.center)
                .lineLimit(Type.cardTitleLines)
            Text(status)
                .font(Type.caption)
                .foregroundStyle(Ink.soft)
        }
        .frame(width: Size.cardWidth)
        .accessibilityElement(children: .ignore)
        // A card with no status yet - a document never opened, still being sized -
        // would otherwise be read out with a comma and then nothing.
        .accessibilityLabel(status.isEmpty ? title : "\(title), \(status)")
    }
}
