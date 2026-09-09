import SwiftUI

public enum Space {
    /// Rows that carry their own vertical padding stack flush.
    public static let none: CGFloat = 0
    public static let xs: CGFloat = 4
    public static let s: CGFloat = 8
    public static let m: CGFloat = 12
    public static let l: CGFloat = 16
    public static let xl: CGFloat = 24
    public static let xxl: CGFloat = 32
    public static let xxxl: CGFloat = 48
}

public enum Radius {
    public static let s: CGFloat = 8
    public static let m: CGFloat = 12
    public static let l: CGFloat = 20
}

public enum Size {
    public static let icon: CGFloat = 16
    public static let control: CGFloat = 32
    public static let playControl: CGFloat = 44
    public static let hairline: CGFloat = 1
    public static let cardWidth: CGFloat = 160
    public static let thumb = CGSize(width: 120, height: 150)
    public static let minWindow = CGSize(width: 720, height: 480)
    public static let readerMeasure: CGFloat = 680
    /// The measure plus the text container's inset on each side.
    public static let readerFrame: CGFloat = readerMeasure + Space.xxl + Space.xxl
    /// Where an auto-scrolled sentence lands: one third down the visible text.
    public static let readerFollowFraction: CGFloat = 1.0 / 3.0
    public static let scrubberTrack: CGFloat = 4
    /// The voice popover: wide enough for a name, a region and a quality on one line,
    /// tall enough for a section header and about eight voices under it.
    public static let popoverWidth: CGFloat = 320
    public static let popoverHeight: CGFloat = 440
}

public enum Ink {
    public static let primary = Color.primary
    public static let soft = Color.secondary
    public static let accent = Color.accentColor
    public static let paper = Color(nsColor: .textBackgroundColor)
    public static let highlightSentence = Color.accentColor.opacity(0.18)
    public static let highlightWord = Color.accentColor.opacity(0.45)
    public static let nsHighlightSentence = NSColor.controlAccentColor.withAlphaComponent(0.18)
    public static let nsHighlightWord = NSColor.controlAccentColor.withAlphaComponent(0.45)
    public static let track = Color.secondary.opacity(0.3)
    public static let thumbPaper = Color.white
    public static let thumbInk = Color.black
}

public enum Type {
    public static let title = Font.title2.weight(.semibold)
    public static let cardTitle = Font.callout.weight(.medium)
    public static let caption = Font.caption
    public static let control = Font.body.weight(.medium)
    public static let thumb = Font.system(size: 3, design: .monospaced)
    /// The five reader sizes, indexed by the A/A stepper.
    public static let readerSizes: [CGFloat] = [15, 17, 19, 22, 26]
    public static let readerDefaultIndex = 1
    /// A card's title is truncated to two lines, so a long first line cannot push the
    /// status off the bottom of the cell.
    public static let cardTitleLines = 2
    public static let readerLineHeightMultiple: CGFloat = 1.45
}

public enum Motion {
    public static let fast: Double = 0.15
    public static let normal: Double = 0.25
    public static let ease = Animation.easeOut(duration: normal)
    public static let quick = Animation.easeOut(duration: fast)
    /// How long the search field waits after the last keystroke before it reads files.
    public static let searchDebounceMS: Double = 200
}
