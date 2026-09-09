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
            // The preview is a picture of the file, unreadably small on purpose, so it
            // is decoration; the label below carries the same words for a reader.
            Text(preview)
                .font(Type.thumb)
                .foregroundStyle(Ink.thumbInk)
                .frame(width: Size.thumb.width, height: Size.thumb.height, alignment: .topLeading)
                .padding(Space.s)
                .background(Ink.thumbPaper, in: .rect(cornerRadius: Radius.s))
                .clipped()
                .accessibilityHidden(true)
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
        .accessibilityLabel("\(title), \(status)")
    }
}
