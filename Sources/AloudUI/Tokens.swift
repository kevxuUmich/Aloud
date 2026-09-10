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
    /// A corner that is not there: the two bottom corners of a bar docked to the
    /// window's edge, which has no edge of its own to round against.
    public static let none: CGFloat = 0
    public static let s: CGFloat = 8
    public static let m: CGFloat = 12
    public static let l: CGFloat = 20
    /// The two top corners of the docked transport bar.
    public static let dockedTop: CGFloat = l
    /// The glyph plate in the clipboard panel.
    public static let plate: CGFloat = m
}

public enum Size {
    public static let icon: CGFloat = 16
    /// The landing page's glyph, and the measure its lines of copy wrap at.
    public static let landingGlyph: CGFloat = 96
    public static let landingMeasure: CGFloat = 420
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
    /// tall enough for the search field, a section header and about eight voices.
    public static let popoverWidth: CGFloat = 320
    public static let popoverHeight: CGFloat = 520
    /// The menu-bar panel: the popover's width, so the two read as one control.
    public static let panelWidth: CGFloat = 320
    /// The volume slider in the transport bar: long enough to set a level by eye,
    /// short enough to sit beside the speed without crowding it.
    public static let volumeSlider: CGFloat = 88
    /// The menu bar's item: the mark at the height a symbol takes there.
    public static let menuBarGlyph: CGFloat = 18
    /// The Settings window: wide enough for a folder's name, its two buttons and the
    /// hotkey recorder on one line, and no wider, since a Form's rows are labelled at
    /// the left and stretch would only push the controls away from their labels.
    public static let settingsWidth: CGFloat = 520
    /// The clipboard panel under the menu bar, and the square glyph plate at its left:
    /// the Now Playing card's own proportions, so the two read as the same thing.
    public static let clipboardPanelWidth: CGFloat = 360
    public static let clipboardPlate: CGFloat = 88
    /// The mark inside the plate: drawn in the plate's own frame, so the ring fills the
    /// plate the way it fills the icon's tile, and the plate reads as the icon.
    public static let clipboardGlyph: CGFloat = clipboardPlate
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
    /// The mark's own colour, the icon's ring: the midpoint of its lit and shaded
    /// edges, sampled from the 1024 export. The landing page and the plates draw the
    /// mark in it; the menu bar takes the bar's tint instead.
    public static let mark = Color(.sRGB, red: 0xED / 255.0, green: 0xDB / 255.0, blue: 0xEE / 255.0)
    public static let landingGlyph = mark
    /// The plates in the clipboard panel and on the Now Playing card: the icon's own
    /// dark plate, with the mark in its own colour on it.
    public static let plate = Color(.sRGB, red: 0x2A / 255.0, green: 0x2A / 255.0, blue: 0x2B / 255.0)
    public static let plateGlyph = mark
}

public enum Type {
    public static let title = Font.title2.weight(.semibold)
    /// The landing page, which is the whole window and carries the type to match.
    public static let landingTitle = Font.largeTitle.weight(.semibold)
    public static let landingBody = Font.title3
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
    /// The gap between two paragraphs, as a share of the reader's font size. The
    /// source keeps a blank line between paragraphs, and that line is drawn at this
    /// height rather than a line of prose's: at the prose's own height, plus the
    /// paragraph spacing that used to sit either side of it, the gap read as two lines.
    public static let readerParagraphGap: CGFloat = 0.75
    /// The menu-bar panel's sentence, truncated so the panel keeps its height.
    public static let panelSentenceLines = 3
    /// One line and no more: a list row's title, the panel's title, the transport's.
    public static let singleLine = 1
    /// The clipboard panel's two lines, the card's title and its subtitle.
    public static let panelTitle = Font.headline
    public static let panelSubtitle = Font.subheadline
}

public enum Motion {
    public static let fast: Double = 0.15
    public static let normal: Double = 0.25
    public static let ease = Animation.easeOut(duration: normal)
    public static let quick = Animation.easeOut(duration: fast)
    /// How long the search field waits after the last keystroke before it reads files.
    public static let searchDebounceMS: Double = 200
    /// A control that is present but has nothing to act on: the menu-bar glyph with
    /// no document loaded.
    public static let dimmed: Double = 0.5
    /// How long the panel stays when the clipboard has no text: long enough to read
    /// two short lines, not long enough to reach for the mouse.
    public static let emptyPanelHold: Double = 1.6
}

/// The aperture mark: a ring on the superellipse shape law, open at the lower right.
/// Four numbers describe it, taken from the mark's own SVG in a 96-point frame: the
/// exponent of the law, the ring's box as a share of the frame, the stroke as a share
/// of the frame, and half the opening in degrees, measured as a polar angle from the
/// flat side that faces the lower-right diagonal.
public enum Mark {
    public static let exponent: CGFloat = 2.8
    public static let body: CGFloat = 68.0 / 96.0
    public static let stroke: CGFloat = 9.0 / 96.0
    public static let gapHalfAngle: CGFloat = 13.6
    /// How many straight pieces the outline is drawn with: one per degree.
    public static let samples = 360
    /// The turn that brings a flat side of the ring onto the lower-right diagonal.
    public static let turnDegrees: CGFloat = 45
}
