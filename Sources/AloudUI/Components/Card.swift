import AppKit
import SwiftUI

public struct Card: View {
    public let title: String
    public let preview: String
    public let status: String
    /// A bookmark on the document: a filled ribbon in the accent, at the page's top
    /// right corner, where a ribbon hangs over a real page.
    public let bookmarked: Bool
    /// Selected in the library: a plate in the accent under the whole card, picture
    /// and words, the way Finder plates an icon and its name.
    public let selected: Bool
    /// The icon of the app the text came from, for a note the panel wrote: set in the
    /// middle of the page, as the Finder sets an app's badge on its documents.
    public let icon: NSImage?
    public init(
        title: String, preview: String, status: String, bookmarked: Bool = false,
        selected: Bool = false, icon: NSImage? = nil
    ) {
        self.title = title
        self.preview = preview
        self.status = status
        self.bookmarked = bookmarked
        self.selected = selected
        self.icon = icon
    }
    public var body: some View {
        VStack(spacing: Space.s) {
            // The label below carries the picture's words for a reader.
            Thumb(preview: preview, scale: .card)
                .overlay {
                    if let icon {
                        Image(nsImage: icon)
                            .resizable()
                            .interpolation(.high)
                            .frame(width: Size.cardIcon, height: Size.cardIcon)
                            // The icon's own margin is clear, and the page's words
                            // would show through it and around its corners. Paper
                            // under the whole frame masks them, so the icon sits in a
                            // clearing on the page rather than over the text.
                            .background(
                                Ink.thumbPaper,
                                in: .rect(cornerRadius: Radius.cardIconClearing, style: .continuous)
                            )
                            .accessibilityHidden(true)
                    }
                }
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
        .background {
            // Inset outward rather than padded, so a selected card is the same size
            // and the grid does not shift when the selection does.
            RoundedRectangle(cornerRadius: Radius.selection, style: .continuous)
                .fill(selected ? Ink.selection : .clear)
                .padding(-Space.s)
        }
        .accessibilityElement(children: .ignore)
        .accessibilityAddTraits(selected ? .isSelected : [])
        // A card with no status yet - a document never opened, still being sized -
        // would otherwise be read out with a comma and then nothing.
        .accessibilityLabel(
            [title, status, bookmarked ? "Bookmarked" : ""].filter { !$0.isEmpty }.joined(separator: ", "))
    }
}
