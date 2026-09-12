import AppKit
import ApplicationServices

/// The text selected in the app in front, read through Accessibility: the focused
/// element's selected text, which is what most apps expose. Some do not, and the
/// hotkey falls back to the clipboard for those, so copying still works everywhere.
enum Selection {
    /// Whether Aloud has the Accessibility grant, without which nothing below answers.
    static var isTrusted: Bool { AXIsProcessTrusted() }

    /// The system's prompt, which also adds Aloud to the list in System Settings.
    static func ask() {
        // The option's key, spelled out rather than read from `kAXTrustedCheckOptionPrompt`:
        // that global is an `Unmanaged` C constant Swift 6 cannot prove safe to touch.
        let options = ["AXTrustedCheckOptionPrompt": true] as CFDictionary
        _ = AXIsProcessTrustedWithOptions(options)
    }

    /// The pane the grant lives in, for the button in Settings.
    static func openSettings() {
        let url = URL(
            string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility")!
        NSWorkspace.shared.open(url)
    }

    /// The selected text of whatever has keyboard focus, or nil when there is none, the
    /// app does not say, or the grant is missing.
    static func text() -> String? {
        var focused: CFTypeRef?
        let system = AXUIElementCreateSystemWide()
        guard
            AXUIElementCopyAttributeValue(system, kAXFocusedUIElementAttribute as CFString, &focused)
                == .success, let focused, CFGetTypeID(focused) == AXUIElementGetTypeID()
        else { return nil }
        // Checked by type id above; `as?` cannot see through a CF type from Swift.
        let element = unsafeDowncast(focused, to: AXUIElement.self)
        var value: CFTypeRef?
        guard
            AXUIElementCopyAttributeValue(element, kAXSelectedTextAttribute as CFString, &value)
                == .success
        else { return nil }
        return value as? String
    }
}
