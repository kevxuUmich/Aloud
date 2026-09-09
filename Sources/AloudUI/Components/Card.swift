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
            Text(preview)
                .font(Type.thumb)
                .foregroundStyle(Ink.thumbInk)
                .frame(width: Size.thumb.width, height: Size.thumb.height, alignment: .topLeading)
                .padding(Space.s)
                .background(Ink.thumbPaper, in: .rect(cornerRadius: Radius.s))
                .clipped()
            Text(title)
                .font(Type.cardTitle)
                .multilineTextAlignment(.center)
                .lineLimit(2)
            Text(status)
                .font(Type.caption)
                .foregroundStyle(Ink.soft)
        }
        .frame(width: Size.cardWidth)
    }
}
