import AloudUI
import AppKit
import SwiftUI

/// The document body. TextKit 1 on purpose: the sentence and word highlights are
/// temporary attributes, which only `NSLayoutManager` carries, and an `NSTextView`
/// built from an explicit storage/layout/container stack is TextKit 1 by construction
/// rather than by the accidental downgrade that touching `layoutManager` would cause.
struct ReaderTextView: NSViewRepresentable {
    var text: String
    var fontSize: CGFloat
    /// The prose's design, sans or serif; the size and this together are the font.
    var design: NSFontDescriptor.SystemDesign = .default
    var sentence: NSRange?
    var word: NSRange?
    var follow: Bool
    var editable: Bool
    /// The notice floating over the top of the window: the text starts below it and
    /// scrolls beneath it. An inset on the scroll view, not a smaller frame, because
    /// the scroll view's top edge against the toolbar is what keeps the toolbar from
    /// drawing a line under itself.
    var topInset: CGFloat = .zero
    var onClick: (Int) -> Void
    var onEdit: (String) -> Void
    var onBlur: () -> Void
    var onUserScroll: () -> Void

    func makeCoordinator() -> Coordinator { Coordinator(self) }

    func makeNSView(context: Context) -> ReaderScrollView {
        let scroll = Self.makeScrollView()
        let tv = scroll.documentView as! ClickableTextView
        tv.coordinator = context.coordinator
        tv.delegate = context.coordinator
        NotificationCenter.default.addObserver(
            context.coordinator, selector: #selector(Coordinator.scrolled),
            name: NSScrollView.willStartLiveScrollNotification, object: scroll)
        return scroll
    }

    /// The scroll view and the text view inside it, without the coordinator, so the
    /// suite can build the same stack and measure it.
    static func makeScrollView() -> ReaderScrollView {
        let storage = NSTextStorage()
        let layout = NSLayoutManager()
        let container = NSTextContainer(
            size: NSSize(width: CGFloat.zero, height: CGFloat.greatestFiniteMagnitude))
        container.widthTracksTextView = true
        storage.addLayoutManager(layout)
        layout.addTextContainer(container)

        let scroll = ReaderScrollView()
        let tv = ClickableTextView(frame: .zero, textContainer: container)
        tv.autoresizingMask = [.width]
        tv.isVerticallyResizable = true
        tv.isHorizontallyResizable = false
        // A text view's `maxSize` defaults to its frame, and the frame is whatever the
        // scroll view first lays it out at - one screenful. Vertically resizable only
        // means resizable up to that, so the document stopped at the first screen's
        // height and the rest of the file was never reachable.
        tv.minSize = .zero
        tv.maxSize = NSSize(
            width: CGFloat.greatestFiniteMagnitude, height: CGFloat.greatestFiniteMagnitude)
        tv.isEditable = false
        tv.isSelectable = false
        tv.isRichText = false
        tv.drawsBackground = false
        tv.textContainerInset = NSSize(width: Space.xxl, height: Space.xxl)
        tv.setAccessibilityRole(.staticText)
        scroll.documentView = tv
        scroll.drawsBackground = false
        scroll.hasVerticalScroller = true
        return scroll
    }

    /// The prose's attributes, and the blank line between paragraphs drawn at the
    /// paragraph gap rather than at a line of prose's height. The source is the
    /// script the sentences are indexed into, so the blank line stays in the text and
    /// only its height changes. Returns the prose attributes, for the typing ones.
    static func style(
        _ storage: NSTextStorage, fontSize: CGFloat, design: NSFontDescriptor.SystemDesign = .default
    ) -> [NSAttributedString.Key: Any] {
        let all = NSRange(location: 0, length: storage.length)
        let font = Self.font(size: fontSize, design: design)
        let paragraph = NSMutableParagraphStyle()
        paragraph.lineHeightMultiple = Type.readerLineHeightMultiple
        let attributes: [NSAttributedString.Key: Any] = [
            .font: font,
            .paragraphStyle: paragraph,
            .foregroundColor: NSColor.labelColor,
        ]
        storage.setAttributes(attributes, range: all)
        let gap = NSMutableParagraphStyle()
        gap.minimumLineHeight = fontSize * Type.readerParagraphGap
        gap.maximumLineHeight = fontSize * Type.readerParagraphGap
        // Of a "\n\n", the second newline is an empty paragraph of its own.
        let text = storage.string as NSString
        var at = 0
        while at < text.length {
            let r = text.range(of: "\n\n", range: NSRange(location: at, length: text.length - at))
            guard r.location != NSNotFound else { break }
            storage.addAttribute(
                .paragraphStyle, value: gap, range: NSRange(location: r.location + 1, length: 1))
            at = r.location + 2
        }
        return attributes
    }

    /// The system font in the given design. A design the system cannot supply, which
    /// none of the reader's are, leaves the plain system font rather than nothing.
    static func font(size: CGFloat, design: NSFontDescriptor.SystemDesign) -> NSFont {
        let plain = NSFont.systemFont(ofSize: size)
        guard design != .default, let d = plain.fontDescriptor.withDesign(design) else { return plain }
        return NSFont(descriptor: d, size: size) ?? plain
    }

    /// Where the clip view's origin goes to show `sentence` a third of the way down
    /// the text, or to the top with no sentence to show.
    static func target(for sentence: NSRange?, in scroll: NSScrollView) -> CGFloat {
        let top = -scroll.contentInsets.top
        guard let sentence, let tv = scroll.documentView as? NSTextView, let lm = tv.layoutManager,
            let container = tv.textContainer, NSMaxRange(sentence) <= (tv.string as NSString).length
        else { return top }
        let inset = tv.textContainerInset.height
        let glyphs = lm.glyphRange(forCharacterRange: sentence, actualCharacterRange: nil)
        let rect = lm.boundingRect(forGlyphRange: glyphs, in: container)
        return followTarget(
            sentenceTop: rect.minY + inset,
            documentHeight: lm.usedRect(for: container).height + inset + inset,
            clipHeight: scroll.contentView.bounds.height, topInset: scroll.contentInsets.top)
    }

    /// The document at `sentence` at once, with no animation: where a document stands
    /// when it opens, or when its text is replaced under the reader.
    static func place(_ scroll: NSScrollView, at sentence: NSRange?) {
        if let tv = scroll.documentView as? NSTextView, let lm = tv.layoutManager,
            let container = tv.textContainer
        {
            lm.ensureLayout(for: container)
        }
        let clip = scroll.contentView
        clip.setBoundsOrigin(NSPoint(x: .zero, y: target(for: sentence, in: scroll)))
        scroll.reflectScrolledClipView(clip)
    }

    /// Where the clip view's origin goes to follow a sentence: a third of the way down
    /// the text that shows, which is the clip below the top inset. The first screenful
    /// cannot be pulled further down than the inset lets it, nor the last one pushed
    /// further up than its end, so the target is clamped to the scrollable range.
    static func followTarget(
        sentenceTop: CGFloat, documentHeight: CGFloat, clipHeight: CGFloat, topInset: CGFloat
    ) -> CGFloat {
        let visible = clipHeight - topInset
        let wanted = sentenceTop - topInset - visible * Size.readerFollowFraction
        let bottom = max(-topInset, documentHeight - clipHeight)
        return min(max(-topInset, wanted), bottom)
    }

    /// The top inset, applied only when it changes. The clip view keeps what it was
    /// showing where it shows: the line at the top of the text stays the first line
    /// below a notice that arrives, at the top of a document or in the middle of one,
    /// and comes back up when the notice goes.
    static func setTopInset(_ inset: CGFloat, on scroll: NSScrollView) {
        guard scroll.contentInsets.top != inset else { return }
        scroll.automaticallyAdjustsContentInsets = false
        scroll.contentInsets = NSEdgeInsets(top: inset, left: .zero, bottom: .zero, right: .zero)
    }

    static func dismantleNSView(_ scroll: ReaderScrollView, coordinator: Coordinator) {
        NotificationCenter.default.removeObserver(
            coordinator, name: NSScrollView.willStartLiveScrollNotification, object: scroll)
    }

    func updateNSView(_ scroll: ReaderScrollView, context: Context) {
        guard let tv = scroll.documentView as? ClickableTextView, let storage = tv.textStorage,
            let lm = tv.layoutManager, let container = tv.textContainer
        else { return }
        let co = context.coordinator
        co.parent = self
        Self.setTopInset(topInset, on: scroll)

        let all = NSRange(location: 0, length: (text as NSString).length)
        // The size is cached rather than read back off `tv.font`, and the length is
        // compared before the string: both of these run on every spoken word.
        let resized = co.appliedFontSize != fontSize || co.appliedDesign != design
        let replaced = storage.length != all.length || tv.string != text
        if replaced {
            tv.string = text
            // `string` leaves the insertion point after the last character, and a text
            // view in a window scrolls its insertion point into view: a document opened
            // at its last screenful rather than at the sentence being read.
            tv.setSelectedRange(NSRange(location: 0, length: 0))
        }
        if replaced || resized {
            // Assigning `font` re-applies over the whole storage, so it is set only
            // when the font actually changed, and before `style` lays its own over it.
            if resized { tv.font = Self.font(size: fontSize, design: design) }
            tv.typingAttributes = Self.style(storage, fontSize: fontSize, design: design)
            co.appliedFontSize = fontSize
            co.appliedDesign = design
            // New text or a new size moves every line, so where we last scrolled to
            // says nothing about where the current sentence is now.
            co.lastScrolledTo = nil
        }
        tv.isEditable = editable
        tv.isSelectable = editable
        tv.setAccessibilityRole(editable ? .textArea : .staticText)
        if resized {
            lm.invalidateLayout(forCharacterRange: all, actualCharacterRange: nil)
            lm.ensureLayout(for: container)
        }
        // Following has just been switched back on, by a click or by play. The reader
        // scrolled away by hand meanwhile, so the current sentence has to be scrolled
        // to again even though it is the one we last scrolled to.
        if follow, !co.wasFollowing { co.lastScrolledTo = nil }
        co.wasFollowing = follow

        // New text is placed once the scroll view has its size: at the sentence being
        // read, where following would have put it, or at the top. Placed any earlier,
        // the clip view has no height to measure a third of, and the top inset is laid
        // over an origin the first layout then resets.
        if replaced, !editable {
            co.lastScrolledTo = sentence
            scroll.placeAfterLayout { [weak co] scroll in
                Self.place(scroll, at: co?.parent.sentence)
            }
        }

        lm.removeTemporaryAttribute(.backgroundColor, forCharacterRange: all)
        guard let s = sentence, !editable, NSMaxRange(s) <= all.length else { return }
        lm.addTemporaryAttribute(
            .backgroundColor, value: Ink.nsHighlightSentence, forCharacterRange: s)
        if let w = word, NSMaxRange(w) <= all.length {
            lm.addTemporaryAttribute(.backgroundColor, value: Ink.nsHighlightWord, forCharacterRange: w)
        }
        guard follow, s != co.lastScrolledTo else { return }
        co.lastScrolledTo = s
        co.programmatic = true
        let clip = scroll.contentView
        let target = Self.target(for: s, in: scroll)
        NSAnimationContext.runAnimationGroup { ctx in
            ctx.duration = Motion.normal
            clip.animator().setBoundsOrigin(NSPoint(x: .zero, y: target))
        } completionHandler: {
            MainActor.assumeIsolated {
                scroll.reflectScrolledClipView(clip)
                co.programmatic = false
            }
        }
    }

    @MainActor
    final class Coordinator: NSObject, NSTextViewDelegate {
        var parent: ReaderTextView
        var lastScrolledTo: NSRange?
        var programmatic = false
        var wasFollowing = false
        var appliedFontSize: CGFloat?
        var appliedDesign: NSFontDescriptor.SystemDesign?
        init(_ p: ReaderTextView) { parent = p }
        @objc func scrolled() { if !programmatic { parent.onUserScroll() } }
        func textDidChange(_ n: Notification) {
            guard let tv = n.object as? NSTextView else { return }
            parent.onEdit(tv.string)
        }
        /// The editor losing first responder: a click elsewhere, another window coming
        /// forward. The draft is written rather than left hanging on a button press.
        func textDidEndEditing(_ n: Notification) { parent.onBlur() }
    }
}

/// The reader's scroll view, which can hold a placement back until it has been laid
/// out: the first update reaches the view before it has a size, and an origin set then
/// is measured against nothing and reset by the layout that follows.
final class ReaderScrollView: NSScrollView {
    private var pendingPlacement: ((ReaderScrollView) -> Void)?

    /// Runs `placement` after the next layout that leaves the clip view a height, and
    /// only the latest one asked for.
    func placeAfterLayout(_ placement: @escaping (ReaderScrollView) -> Void) {
        pendingPlacement = placement
        needsLayout = true
    }

    override func layout() {
        super.layout()
        guard contentView.bounds.height > .zero, let placement = pendingPlacement else { return }
        pendingPlacement = nil
        placement(self)
    }
}

/// A click on the prose is a seek, not a caret placement, unless the reader is editing.
final class ClickableTextView: NSTextView {
    weak var coordinator: ReaderTextView.Coordinator?

    override func mouseDown(with event: NSEvent) {
        guard !isEditable else { return super.mouseDown(with: event) }
        guard let index = characterIndex(under: convert(event.locationInWindow, from: nil)) else {
            return
        }
        coordinator?.parent.onClick(index)
    }

    /// Scrolling by keyboard is scrolling: page up and down, the arrows, and space,
    /// which pages a text view that is not being edited. Each cancels follow the way a
    /// drag on the scroller does, so the reader who has gone looking is not dragged
    /// back at the next sentence. In the editor these keys move the caret and the
    /// reader is not following anything, so nothing is cancelled.
    override func keyDown(with event: NSEvent) {
        if !isEditable, Self.scrollKeys.contains(Int(event.keyCode)) {
            coordinator?.parent.onUserScroll()
        }
        super.keyDown(with: event)
    }

    /// Page up, page down, home, end, the four arrows, and space.
    private static let scrollKeys: Set<Int> = [116, 121, 115, 119, 123, 124, 125, 126, 49]

    /// A wheel or a two-finger swipe. `willStartLiveScroll` covers the scroller and
    /// the drag; the momentum a trackpad throws afterwards arrives here alone.
    override func scrollWheel(with event: NSEvent) {
        coordinator?.parent.onUserScroll()
        super.scrollWheel(with: event)
    }

    /// The character actually under `point`, or nil when the point is in the padding,
    /// past the end of a line, or below the last line. `characterIndexForInsertion`
    /// answers with the nearest character everywhere, which would turn a click on the
    /// empty space below the text into a seek to the last sentence.
    private func characterIndex(under point: NSPoint) -> Int? {
        guard let lm = layoutManager, let container = textContainer else { return nil }
        let inContainer = NSPoint(
            x: point.x - textContainerInset.width, y: point.y - textContainerInset.height)
        let insertion = characterIndexForInsertion(at: point)
        // An insertion index rounds forward through the glyph it lands in, so on the
        // right half of a line's last character it names the first character of the
        // next line, a line below the point. Try the character before it as well
        // before calling the point dead space.
        if covers(insertion, inContainer, lm, container) { return insertion }
        if covers(insertion - 1, inContainer, lm, container) { return insertion - 1 }
        return nil
    }

    private func covers(
        _ index: Int, _ point: NSPoint, _ lm: NSLayoutManager, _ container: NSTextContainer
    ) -> Bool {
        guard index >= 0, index < (string as NSString).length else { return false }
        let glyphs = lm.glyphRange(
            forCharacterRange: NSRange(location: index, length: 1), actualCharacterRange: nil)
        guard glyphs.length > 0 else { return false }
        let bounds = lm.boundingRect(forGlyphRange: glyphs, in: container)
        guard bounds.minY <= point.y, point.y <= bounds.maxY else { return false }
        let line = lm.lineFragmentUsedRect(forGlyphAt: glyphs.location, effectiveRange: nil)
        return line.minX <= point.x && point.x <= line.maxX
    }
}
