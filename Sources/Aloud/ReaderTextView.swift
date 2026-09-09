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
    var sentence: NSRange?
    var word: NSRange?
    var follow: Bool
    var editable: Bool
    var onClick: (Int) -> Void
    var onEdit: (String) -> Void
    var onBlur: () -> Void
    var onUserScroll: () -> Void

    func makeCoordinator() -> Coordinator { Coordinator(self) }

    func makeNSView(context: Context) -> NSScrollView {
        let storage = NSTextStorage()
        let layout = NSLayoutManager()
        let container = NSTextContainer(
            size: NSSize(width: CGFloat.zero, height: CGFloat.greatestFiniteMagnitude))
        container.widthTracksTextView = true
        storage.addLayoutManager(layout)
        layout.addTextContainer(container)

        let scroll = NSScrollView()
        let tv = ClickableTextView(frame: .zero, textContainer: container)
        tv.autoresizingMask = [.width]
        tv.isVerticallyResizable = true
        tv.isHorizontallyResizable = false
        tv.isEditable = false
        tv.isSelectable = false
        tv.isRichText = false
        tv.drawsBackground = false
        tv.textContainerInset = NSSize(width: Space.xxl, height: Space.xxl)
        tv.coordinator = context.coordinator
        tv.delegate = context.coordinator
        tv.setAccessibilityRole(.staticText)
        scroll.documentView = tv
        scroll.drawsBackground = false
        scroll.hasVerticalScroller = true
        NotificationCenter.default.addObserver(
            context.coordinator, selector: #selector(Coordinator.scrolled),
            name: NSScrollView.willStartLiveScrollNotification, object: scroll)
        return scroll
    }

    static func dismantleNSView(_ scroll: NSScrollView, coordinator: Coordinator) {
        NotificationCenter.default.removeObserver(
            coordinator, name: NSScrollView.willStartLiveScrollNotification, object: scroll)
    }

    func updateNSView(_ scroll: NSScrollView, context: Context) {
        guard let tv = scroll.documentView as? ClickableTextView, let storage = tv.textStorage,
            let lm = tv.layoutManager, let container = tv.textContainer
        else { return }
        let co = context.coordinator
        co.parent = self

        let all = NSRange(location: 0, length: (text as NSString).length)
        // The size is cached rather than read back off `tv.font`, and the length is
        // compared before the string: both of these run on every spoken word.
        let resized = co.appliedFontSize != fontSize
        let replaced = storage.length != all.length || tv.string != text
        if replaced { tv.string = text }
        if replaced || resized {
            let paragraph = NSMutableParagraphStyle()
            paragraph.lineHeightMultiple = Type.readerLineHeightMultiple
            paragraph.paragraphSpacing = fontSize
            let attributes: [NSAttributedString.Key: Any] = [
                .font: NSFont.systemFont(ofSize: fontSize),
                .paragraphStyle: paragraph,
                .foregroundColor: NSColor.labelColor,
            ]
            // Assigning `font` re-applies over the whole storage, so it is set only
            // when the size actually changed.
            if resized { tv.font = NSFont.systemFont(ofSize: fontSize) }
            storage.setAttributes(attributes, range: all)
            tv.typingAttributes = attributes
            co.appliedFontSize = fontSize
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
        let inset = tv.textContainerInset.height
        let glyphs = lm.glyphRange(forCharacterRange: s, actualCharacterRange: nil)
        var rect = lm.boundingRect(forGlyphRange: glyphs, in: container)
        rect.origin.y += inset
        let clip = scroll.contentView
        // The last screenful of a document cannot be pushed any further up, so the
        // target is clamped to the bottom of the scrollable range.
        let documentHeight = lm.usedRect(for: container).height + inset + inset
        let bottom = max(0, documentHeight - clip.bounds.height)
        let wanted = rect.minY - clip.bounds.height * Size.readerFollowFraction
        let target = min(max(0, wanted), bottom)
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
