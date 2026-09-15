import AppKit
import AloudUI
import Testing

@testable import Aloud

/// The reader's text view, measured headless: the stack `makeScrollView` builds is
/// the one the reader shows, and the attributes `style` lays are the ones it reads.
@Suite @MainActor struct ReaderTextViewTests {
    static let fontSize: CGFloat = Type.readerSizes[Type.readerDefaultIndex]

    func laidOut(_ text: String) -> (NSScrollView, NSTextView, NSLayoutManager, NSTextContainer) {
        let scroll = ReaderTextView.makeScrollView()
        scroll.frame = NSRect(x: 0, y: 0, width: 800, height: 600)
        scroll.layoutSubtreeIfNeeded()
        let tv = scroll.documentView as! NSTextView
        tv.string = text
        _ = ReaderTextView.style(tv.textStorage!, fontSize: Self.fontSize)
        tv.layoutManager!.ensureLayout(for: tv.textContainer!)
        return (scroll, tv, tv.layoutManager!, tv.textContainer!)
    }

    /// Serif puts a serif on every character of the prose, and the paragraph gap's
    /// blank line with it, so the typing attributes and the storage agree.
    @Test func serifIsLaidOverTheWholeStorage() {
        let (_, tv, _, _) = laidOut("One.\n\nTwo.")
        let typing = ReaderTextView.style(tv.textStorage!, fontSize: Self.fontSize, design: .serif)
        let font = typing[.font] as! NSFont
        let serif = ReaderTextView.font(size: Self.fontSize, design: .serif)
        #expect(serif.familyName != NSFont.systemFont(ofSize: Self.fontSize).familyName)
        #expect(font.familyName == serif.familyName)
        #expect(font.pointSize == Self.fontSize)
        let storage = tv.textStorage!
        let last = storage.attribute(.font, at: storage.length - 1, effectiveRange: nil) as! NSFont
        #expect(last.familyName == serif.familyName)
    }

    /// The whole file, not the first screen of it: the view grows to its layout. It
    /// did not, once, because `maxSize` defaulted to the first frame the scroll view
    /// gave it, and every line past that height was unreachable.
    @Test func theViewGrowsToTheWholeDocument() {
        let paragraph = "Lorem ipsum dolor sit amet, consectetur adipiscing elit, sed do eiusmod."
        let (scroll, tv, lm, container) = laidOut(
            Array(repeating: paragraph, count: 300).joined(separator: "\n\n"))
        let used = lm.usedRect(for: container).height + tv.textContainerInset.height * 2
        #expect(used > scroll.frame.height * 10)
        #expect(abs(tv.frame.height - used) < 1)
    }

    /// The blank line between two paragraphs stands at the paragraph gap, and a line
    /// of prose at the reader's line height; the gap is the whole of what separates
    /// the last line of one paragraph from the first of the next.
    @Test func theParagraphGapIsTheBlankLineAndNothingElse() {
        let (_, _, lm, _) = laidOut("One paragraph.\n\nAnother paragraph.\n\nA third.")
        let text = "One paragraph.\n\nAnother paragraph.\n\nA third." as NSString
        let first = lm.lineFragmentRect(forGlyphAt: 0, effectiveRange: nil)
        let second = lm.lineFragmentRect(
            forGlyphAt: lm.glyphIndexForCharacter(at: text.range(of: "Another").location),
            effectiveRange: nil)
        let gap = second.minY - first.maxY
        #expect(abs(gap - Self.fontSize * Type.readerParagraphGap) < 0.5)
        // Neither of the prose lines carries spacing of its own.
        #expect(first.height == second.height)
        let prose = lm.lineFragmentUsedRect(forGlyphAt: 0, effectiveRange: nil)
        #expect(abs(first.height - prose.height) < 0.5)
    }

    /// With no notice, following is what it always was: a third of the way down the
    /// clip, clamped to the top and to the last screenful.
    @Test func followingWithNoInsetIsAThirdOfTheWayDown() {
        let target = ReaderTextView.followTarget(
            sentenceTop: 1000, documentHeight: 5000, clipHeight: 600, topInset: .zero)
        #expect(target == 1000 - 600 * Size.readerFollowFraction)
        #expect(
            ReaderTextView.followTarget(
                sentenceTop: 10, documentHeight: 5000, clipHeight: 600, topInset: .zero) == .zero)
        #expect(
            ReaderTextView.followTarget(
                sentenceTop: 4990, documentHeight: 5000, clipHeight: 600, topInset: .zero) == 4400)
    }

    /// Under a notice the text that shows starts below it: the third is measured in
    /// what is left, and the first sentence stays below the notice rather than being
    /// scrolled up beneath it.
    @Test func followingUnderANoticeMeasuresTheTextThatShows() {
        let inset: CGFloat = 44
        let target = ReaderTextView.followTarget(
            sentenceTop: 1000, documentHeight: 5000, clipHeight: 600, topInset: inset)
        #expect(target == 1000 - inset - (600 - inset) * Size.readerFollowFraction)
        #expect(
            ReaderTextView.followTarget(
                sentenceTop: 10, documentHeight: 5000, clipHeight: 600, topInset: inset) == -inset)
    }

    /// The line at the top of the text stays the first line below a notice, whether
    /// the document stands at its top or has been scrolled into, and comes back up
    /// when the notice goes.
    @Test func aNoticeKeepsTheTopLineInView() {
        let paragraph = "Lorem ipsum dolor sit amet, consectetur adipiscing elit, sed do eiusmod."
        let (scroll, _, _, _) = laidOut(Array(repeating: paragraph, count: 300).joined(separator: "\n\n"))
        let clip = scroll.contentView
        ReaderTextView.setTopInset(44, on: scroll)
        #expect(scroll.contentInsets.top == 44)
        #expect(clip.bounds.origin.y == -44)
        ReaderTextView.setTopInset(.zero, on: scroll)
        #expect(clip.bounds.origin.y == .zero)

        clip.setBoundsOrigin(NSPoint(x: .zero, y: 900))
        ReaderTextView.setTopInset(44, on: scroll)
        #expect(clip.bounds.origin.y + scroll.contentInsets.top == 900)
        ReaderTextView.setTopInset(.zero, on: scroll)
        #expect(clip.bounds.origin.y == 900)
    }

    /// A document is placed at the sentence being read, a third of the way down, or
    /// at the top with none: never at its last screenful, where setting the text left
    /// the insertion point and the text view scrolled after it.
    @Test func aDocumentIsPlacedAtItsSentenceOrItsTop() {
        let paragraph = "Lorem ipsum dolor sit amet, consectetur adipiscing elit, sed do eiusmod."
        let text = Array(repeating: paragraph, count: 300).joined(separator: "\n\n")
        let (scroll, tv, lm, container) = laidOut(text)
        ReaderTextView.setTopInset(44, on: scroll)
        let sentence = (text as NSString).range(of: paragraph, options: .backwards)
        let middle = NSRange(location: (text as NSString).length / 2, length: 10)

        ReaderTextView.place(scroll, at: middle)
        let inset = tv.textContainerInset.height
        let rect = lm.boundingRect(
            forGlyphRange: lm.glyphRange(forCharacterRange: middle, actualCharacterRange: nil), in: container)
        let expected = ReaderTextView.followTarget(
            sentenceTop: rect.minY + inset,
            documentHeight: lm.usedRect(for: container).height + inset + inset,
            clipHeight: scroll.contentView.bounds.height, topInset: 44)
        #expect(abs(scroll.contentView.bounds.origin.y - expected) < 1)

        ReaderTextView.place(scroll, at: nil)
        #expect(scroll.contentView.bounds.origin.y == -44)

        // The last sentence cannot be brought a third of the way down: the end of the
        // document stops at the bottom of the clip.
        ReaderTextView.place(scroll, at: sentence)
        let bottom = tv.frame.height - scroll.contentView.bounds.height
        #expect(abs(scroll.contentView.bounds.origin.y - bottom) < 1)
    }

    /// A placement asked for before the scroll view has a size waits for the layout
    /// that gives it one, and only the latest placement runs.
    @Test func aPlacementWaitsForASizedLayout() {
        let scroll = ReaderTextView.makeScrollView()
        var ran: [Int] = []
        scroll.placeAfterLayout { _ in ran.append(1) }
        scroll.placeAfterLayout { _ in ran.append(2) }
        scroll.layout()
        #expect(ran.isEmpty)
        scroll.frame = NSRect(x: 0, y: 0, width: 800, height: 600)
        scroll.layoutSubtreeIfNeeded()
        scroll.layout()
        #expect(ran == [2])
        scroll.layout()
        #expect(ran == [2])
    }
}
