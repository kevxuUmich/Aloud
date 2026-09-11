import SwiftUI

public struct Card: View {
    public let title: String
    public let preview: String
    public let status: String
    /// A bookmark on the document: a filled ribbon in the accent, at the page's top
    /// right corner, where a ribbon hangs over a real page.
    public let bookmarked: Bool
    public init(title: String, preview: String, status: String, bookmarked: Bool = false) {
        self.title = title
        self.preview = preview
        self.status = status
        self.bookmarked = bookmarked
    }
    public var body: some View {
        VStack(spacing: Space.s) {
            // The label below carries the picture's words for a reader.
            Thumb(preview: preview, scale: .card)
                .overlay(alignment: .topTrailing) {
                    if bookmarked {
                        Image(systemName: "bookmark.fill")
                            .font(Type.bookmark)
                            .foregroundStyle(Ink.accent)
                            .padding(.trailing, Space.s)
                    }
                }
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
        .accessibilityLabel(
            [title, status, bookmarked ? "Bookmarked" : ""].filter { !$0.isEmpty }.joined(separator: ", "))
    }
}
