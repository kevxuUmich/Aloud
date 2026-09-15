import SwiftUI

/// The picture of a file: its first words on a white plate, unreadably small on
/// purpose, so it is decoration for a label beside it to carry. The card draws it at
/// full size; the transport bar draws the same page at the height of its caption
/// row, so the file on the bar is the file from the library and not a symbol for
/// one. The small one is set in its own type rather than scaled from the large: forty
/// lines shrunk to twenty points is a grey square, and a page is white with lines.
public struct Thumb: View {
    public enum Scale { case card, bar }
    public let preview: String
    public let scale: Scale
    public init(preview: String, scale: Scale = .card) {
        self.preview = preview
        self.scale = scale
    }
    var size: CGSize { scale == .card ? Size.thumb : Size.barThumb }
    var inset: CGFloat { scale == .card ? Space.s : Space.xxs }
    var radius: CGFloat { scale == .card ? Radius.s : Radius.xs }
    var font: Font { scale == .card ? Type.thumb : Type.barThumb }
    public var body: some View {
        Text(preview)
            .font(font)
            .foregroundStyle(Ink.thumbInk)
            .frame(width: size.width, height: size.height, alignment: .topLeading)
            .padding(inset)
            .background(Ink.thumbPaper, in: .rect(cornerRadius: radius))
            // The paper's edge. White on the dark window is its own edge, and white on
            // the light one is no edge at all: the words floated on the window, and a
            // PDF's page, which has no words on it, was not there.
            .overlay {
                RoundedRectangle(cornerRadius: radius).strokeBorder(Ink.thumbEdge, lineWidth: Size.hairline)
            }
            .clipped()
            .accessibilityHidden(true)
    }
}
