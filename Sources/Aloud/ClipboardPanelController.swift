import AloudUI
import AppKit
import SwiftUI

/// Owns the one floating panel and keeps it in step with `model.clipboardPanel`:
/// non-nil orders it front under the menu bar, nil orders it out.
///
/// The panel is non-activating and is made key rather than merely ordered front:
/// Aloud stays inactive and the app in front stays in front, but Enter, Space and
/// Escape reach the panel while it is up, the way they reach Spotlight. Resigning
/// key - a click anywhere else - is the dismissal.
/// The card's Play, as the view in the panel last set it. A key press goes through it
/// so Enter does what a click does in every state.
@MainActor
final class PanelActions {
    var play: () -> Void = {}
}

@MainActor
final class ClipboardPanelController: NSObject, NSWindowDelegate {
    private let model: AppModel
    private let panel: NSPanel
    private let actions = PanelActions()
    private var observation: Task<Void, Never>?
    private var keyMonitor: Any?

    init(model: AppModel) {
        self.model = model
        panel = NSPanel(
            contentRect: .zero, styleMask: [.nonactivatingPanel, .borderless, .fullSizeContentView],
            backing: .buffered, defer: true)
        super.init()
        panel.level = .floating
        panel.hidesOnDeactivate = false
        panel.isFloatingPanel = true
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = true
        panel.isMovable = false
        panel.delegate = self
        let host = NSHostingView(rootView: ClipboardPanelView(model: model, actions: actions))
        host.sizingOptions = [.intrinsicContentSize]
        panel.contentView = host
        observe()
    }

    deinit {
        observation?.cancel()
    }

    /// Re-runs whenever the state flips between nil and not, the way `NowPlaying`
    /// follows the player. Only presence is observed: the view redraws its own contents.
    private func observe() {
        observation = Task { [weak self] in
            let stream = Observations { [weak self] in self?.model.clipboardPanel != nil }
            for await shown in stream {
                guard let self else { return }
                if shown { self.show() } else { self.hide() }
            }
        }
    }

    private func show() {
        panel.contentView?.layoutSubtreeIfNeeded()
        let size = panel.contentView?.fittingSize ?? .zero
        // The screen that carries the menu bar is the one whose origin is the origin,
        // so the panel is in the same place every time, never under the cursor.
        let screen = NSScreen.screens.first { $0.frame.origin == .zero } ?? NSScreen.main
        guard let screen else { return }
        let visible = screen.visibleFrame
        let origin = NSPoint(
            x: visible.midX - size.width / 2, y: visible.maxY - Space.s - size.height)
        panel.setFrame(NSRect(origin: origin, size: size), display: true)
        installKeys()
        panel.makeKeyAndOrderFront(nil)
    }

    private func hide() {
        removeKeys()
        panel.orderOut(nil)
    }

    /// Enter and Space play, Escape dismisses. A local monitor, since the panel is
    /// key while it is up and every keystroke reaches Aloud; the card's own buttons
    /// are the transport's, and these are the shortcuts to them.
    private func installKeys() {
        guard keyMonitor == nil else { return }
        keyMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
            guard let self, self.panel.isKeyWindow else { return event }
            switch event.keyCode {
            case Keys.escape:
                self.model.dismissClipboardPanel()
                return nil
            case Keys.enter, Keys.keypadEnter, Keys.space:
                self.press()
                return nil
            default:
                return event
            }
        }
    }

    private func removeKeys() {
        if let keyMonitor { NSEvent.removeMonitor(keyMonitor) }
        keyMonitor = nil
    }

    /// The same as the card's play button: the view decides what Play means in each
    /// state and hands the decision up, and the key goes through it.
    private func press() {
        actions.play()
    }

    // MARK: NSWindowDelegate

    /// A click anywhere outside: the panel is no longer key, which is the dismissal.
    /// After Play the note stays and keeps playing; only the panel goes.
    func windowDidResignKey(_ notification: Notification) {
        model.dismissClipboardPanel()
    }

    /// The virtual key codes the monitor reads. Carbon's names, without Carbon.
    private enum Keys {
        static let escape: UInt16 = 53
        static let enter: UInt16 = 36
        static let keypadEnter: UInt16 = 76
        static let space: UInt16 = 49
    }
}
