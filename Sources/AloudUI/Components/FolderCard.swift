import SwiftUI

public struct FolderCard: View {
    public let name: String
    public let count: Int
    /// Selected in the library: the same plate a document's card wears.
    public let selected: Bool
    public init(name: String, count: Int, selected: Bool = false) {
        self.name = name
        self.count = count
        self.selected = selected
    }
    public var body: some View {
        VStack(spacing: Space.s) {
            Image(systemName: "folder.fill")
                .resizable().scaledToFit()
                .foregroundStyle(Ink.accent)
                .frame(width: Size.thumb.width, height: Size.thumb.height)
                // The glyph at its own size, in a frame as tall as a document's page,
                // so a folder's name lines up with a document's title beside it.
                .frame(height: Size.thumbPage.height)
                .accessibilityHidden(true)
            // Centred line by line, as a document's title is: a name that wraps
            // otherwise sets its second line against the left of the first.
            Text(name).font(Type.cardTitle).multilineTextAlignment(.center)
                .lineLimit(Type.cardTitleLines)
            Text(Self.status(count: count))
                .font(Type.caption).foregroundStyle(Ink.soft)
        }
        .frame(width: Size.cardWidth)
        .background {
            RoundedRectangle(cornerRadius: Radius.selection, style: .continuous)
                .fill(selected ? Ink.selection : .clear)
                .padding(-Space.s)
        }
        .accessibilityElement(children: .ignore)
        .accessibilityAddTraits(selected ? .isSelected : [])
        // The same words the caption carries, so the two never disagree about an
        // empty folder.
        .accessibilityLabel("\(name), " + Self.status(count: count))
    }

    /// A folder's second line, the card's and the list row's alike: how many documents
    /// are in it, counted in words that agree with the number.
    public static func status(count: Int) -> String {
        switch count {
        case 0: "Empty folder"
        case 1: "1 document"
        default: "\(count) documents"
        }
    }
}
