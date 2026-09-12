import AloudUI
import AppKit
import Speech
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

/// A borderless, non-activating panel answers `canBecomeKey` false, whatever it is
/// asked to do: measured, not assumed, and with it false `makeKeyAndOrderFront` leaves
/// the panel unkeyed, so no key ever reaches it and it can never resign key either -
/// which is the dismissal. The override is what makes the panel a Spotlight rather
/// than a picture. Main is left alone: the window is the app's document, not this.
private final class KeyablePanel: NSPanel {
    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { false }
}

@MainActor
final class ClipboardPanelController: NSObject, NSWindowDelegate {
    private let model: AppModel
    private let panel: NSPanel
    private let actions = PanelActions()
    private var observation: Task<Void, Never>?
    /// The local monitor's token, held outside the actor's isolation so `deinit` -
    /// which is nonisolated even on a `@MainActor` type - can hand it back. It is
    /// written and read on the main thread only, so there is no second thread to race.
    private nonisolated(unsafe) var keyMonitor: Any?

    init(model: AppModel) {
        self.model = model
        panel = KeyablePanel(
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
        // ARC owns the panel through the `let` above, so a close that also released it
        // would be one release too many.
        panel.isReleasedWhenClosed = false
        panel.delegate = self
        let host = NSHostingView(rootView: ClipboardPanelView(model: model, actions: actions))
        host.sizingOptions = [.intrinsicContentSize]
        // The window's shadow is cut to the window's alpha, and glass does not leave
        // the corners clear: its backdrop fills the whole frame, so the shadow came
        // out as a rectangle with a hairline rim standing outside the rounded bar.
        // Clipping the hosting view's layer to the bar's own radius makes the corners
        // truly empty, and the shadow follows the glass.
        host.wantsLayer = true
        host.layer?.cornerRadius = Radius.l
        host.layer?.masksToBounds = true
        panel.contentView = host
        observe()
    }

    deinit {
        observation?.cancel()
        if let keyMonitor { NSEvent.removeMonitor(keyMonitor) }
    }

    /// `Observations` emits on every write to `model.clipboardPanel`, not only on the
    /// flip between nil and not.
    ///
    /// A non-nil emission always re-asserts the panel, because `show()` is idempotent
    /// in effect - it measures, places, installs the keys once and makes the panel key -
    /// and because the stream coalesces: a dismiss and a fresh hotkey inside one turn
    /// arrive as one non-nil emission, and a loop that de-duplicated on presence would
    /// have left the panel unkeyed with the old card still on screen. Only the going
    /// away is de-duplicated, since ordering out a panel that is already out would
    /// churn every redraw a preview makes.
    private func observe() {
        observation = Task { [weak self] in
            var shown = false
            let stream = Observations { [weak self] in self?.model.clipboardPanel != nil }
            for await now in stream {
                guard let self else { return }
                if now {
                    shown = true
                    self.show()
                } else if shown {
                    shown = false
                    self.hide()
                }
            }
        }
    }

    private func show() {
        panel.contentView?.layoutSubtreeIfNeeded()
        let size = panel.contentView?.fittingSize ?? .zero
        // The screen that carries the menu bar is the one whose origin is the origin,
        // so the panel is in the same place every time, never under the cursor.
        let screen = NSScreen.screens.first { $0.frame.origin == .zero } ?? NSScreen.main
        // Nowhere to put it: the state goes too, rather than standing at non-nil with
        // no panel on screen to match it.
        guard let screen else {
            model.dismissClipboardPanel()
            return
        }
        // Centred on the screen rather than on the visible frame: a dock at the left or
        // the right insets the visible frame, and the panel would sit off the menu bar's
        // centre line. The top is the visible frame's, which is under the menu bar.
        let origin = NSPoint(
            x: screen.frame.midX - size.width / 2, y: screen.visibleFrame.maxY - Space.s - size.height)
        panel.setFrame(NSRect(origin: origin, size: size), display: true)
        installKeys()
        panel.makeKeyAndOrderFront(nil)
    }

    private func hide() {
        removeKeys()
        panel.orderOut(nil)
    }

    /// The keys in `PanelKeys`, through a local monitor: the panel is key while it is
    /// up and every keystroke reaches Aloud. The card's own buttons are the
    /// transport's, and these are the shortcuts to them; the arrows step the volume,
    /// and with Option the speed, which the card's second line shows.
    private func installKeys() {
        guard keyMonitor == nil else { return }
        keyMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
            guard let self, self.panel.isKeyWindow,
                let action = PanelKeys.action(keyCode: event.keyCode, modifiers: event.modifierFlags)
            else { return event }
            switch action {
            case .dismiss: self.model.dismissClipboardPanel()
            case .play: self.press()
            case .faster: self.model.setRate(self.model.player.rate.faster)
            case .slower: self.model.setRate(self.model.player.rate.slower)
            case .louder: self.model.setVolume(self.model.player.volume + Player.volumeStep)
            case .quieter: self.model.setVolume(self.model.player.volume - Player.volumeStep)
            }
            return nil
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
}
