import SwiftUI

public struct FolderCard: View {
    public let name: String
    public let count: Int
    public init(name: String, count: Int) {
        self.name = name
        self.count = count
    }
    public var body: some View {
        VStack(spacing: Space.s) {
            Image(systemName: "folder.fill")
                .resizable().scaledToFit()
                .foregroundStyle(Ink.accent)
                .frame(width: Size.thumb.width, height: Size.thumb.height)
                .accessibilityHidden(true)
            Text(name).font(Type.cardTitle).lineLimit(Type.cardTitleLines)
            Text(count == 0 ? "Empty folder" : "\(count) documents")
                .font(Type.caption).foregroundStyle(Ink.soft)
        }
        .frame(width: Size.cardWidth)
        .accessibilityElement(children: .ignore)
        // The same words the caption carries, so the two never disagree about an
        // empty folder.
        .accessibilityLabel("\(name), " + (count == 0 ? "Empty folder" : "\(count) documents"))
    }
}
