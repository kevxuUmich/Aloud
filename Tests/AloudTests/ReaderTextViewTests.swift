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
}
