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

    func updateNSView(_ scroll: NSScrollView, context: Context) {
        guard let tv = scroll.documentView as? ClickableTextView else { return }
        context.coordinator.parent = self
        let all = NSRange(location: 0, length: (text as NSString).length)
        let paragraph = NSMutableParagraphStyle()
        paragraph.lineHeightMultiple = Type.readerLineHeightMultiple
        paragraph.paragraphSpacing = fontSize
        let attributes: [NSAttributedString.Key: Any] = [
            .font: NSFont.systemFont(ofSize: fontSize),
            .paragraphStyle: paragraph,
            .foregroundColor: NSColor.labelColor,
        ]
        // `font` is set only when the size actually changes: assigning it re-applies
        // to the whole storage, and this runs on every word of playback.
        let resized = tv.font?.pointSize != fontSize
        let replaced = tv.string != text
        if replaced { tv.string = text }
        if replaced || resized {
            if resized { tv.font = NSFont.systemFont(ofSize: fontSize) }
            tv.textStorage?.setAttributes(attributes, range: all)
        }
        tv.typingAttributes = attributes
        tv.isEditable = editable
        tv.isSelectable = editable
        tv.setAccessibilityRole(editable ? .textArea : .staticText)

        guard let lm = tv.layoutManager, let container = tv.textContainer else { return }
        if resized {
            lm.invalidateLayout(forCharacterRange: all, actualCharacterRange: nil)
            lm.ensureLayout(for: container)
        }
        lm.removeTemporaryAttribute(.backgroundColor, forCharacterRange: all)
        guard let s = sentence, !editable, NSMaxRange(s) <= all.length else { return }
        lm.addTemporaryAttribute(
            .backgroundColor, value: Ink.nsHighlightSentence, forCharacterRange: s)
        if let w = word, NSMaxRange(w) <= all.length {
            lm.addTemporaryAttribute(.backgroundColor, value: Ink.nsHighlightWord, forCharacterRange: w)
        }
        guard follow, s != context.coordinator.lastScrolledTo else { return }
        context.coordinator.lastScrolledTo = s
        context.coordinator.programmatic = true
        let glyphs = lm.glyphRange(forCharacterRange: s, actualCharacterRange: nil)
        var rect = lm.boundingRect(forGlyphRange: glyphs, in: container)
        rect.origin.y += tv.textContainerInset.height
        let clip = scroll.contentView
        let target = max(0, rect.minY - clip.bounds.height * Size.readerFollowFraction)
        NSAnimationContext.runAnimationGroup { ctx in
            ctx.duration = Motion.normal
            clip.animator().setBoundsOrigin(NSPoint(x: .zero, y: target))
            scroll.reflectScrolledClipView(clip)
        } completionHandler: {
            MainActor.assumeIsolated { context.coordinator.programmatic = false }
        }
    }

    @MainActor
    final class Coordinator: NSObject, NSTextViewDelegate {
        var parent: ReaderTextView
        var lastScrolledTo: NSRange?
        var programmatic = false
        init(_ p: ReaderTextView) { parent = p }
        @objc func scrolled() { if !programmatic { parent.onUserScroll() } }
        func textDidChange(_ n: Notification) {
            guard let tv = n.object as? NSTextView else { return }
            parent.onEdit(tv.string)
        }
    }
}

/// A click anywhere in the prose is a seek, not a caret placement, unless the reader
/// is editing.
final class ClickableTextView: NSTextView {
    weak var coordinator: ReaderTextView.Coordinator?
    override func mouseDown(with event: NSEvent) {
        guard !isEditable else { return super.mouseDown(with: event) }
        let point = convert(event.locationInWindow, from: nil)
        coordinator?.parent.onClick(characterIndexForInsertion(at: point))
    }
}
