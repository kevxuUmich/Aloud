import SwiftUI

public struct ListRow: View {
    public let title: String
    public let status: String
    public let symbol: String
    /// The same ribbon the card wears, before the status, so a list scans for it.
    public let bookmarked: Bool
    /// Selected in the library: the row on a plate in the accent, edge to edge.
    public let selected: Bool
    public init(
        title: String, status: String, symbol: String, bookmarked: Bool = false,
        selected: Bool = false
    ) {
        self.title = title
        self.status = status
        self.symbol = symbol
        self.bookmarked = bookmarked
        self.selected = selected
    }
    public var body: some View {
        HStack(spacing: Space.m) {
            Image(systemName: symbol).foregroundStyle(Ink.soft).accessibilityHidden(true)
            Text(title).font(Type.cardTitle).lineLimit(Type.singleLine)
            Spacer()
            if bookmarked {
                Image(systemName: "bookmark.fill").font(Type.caption).foregroundStyle(Ink.accent)
            }
            Text(status).font(Type.caption).foregroundStyle(Ink.soft)
        }
        .padding(.vertical, Space.s)
        .background {
            RoundedRectangle(cornerRadius: Radius.rowSelection, style: .continuous)
                .fill(selected ? Ink.selection : .clear)
                .padding(.horizontal, -Space.s)
        }
        .accessibilityElement(children: .ignore)
        .accessibilityAddTraits(selected ? .isSelected : [])
        .accessibilityLabel(
            [title, status, bookmarked ? "Bookmarked" : ""].filter { !$0.isEmpty }.joined(separator: ", "))
    }
}
