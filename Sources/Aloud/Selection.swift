import AppKit
import ApplicationServices
import Vault

/// The text selected in the app in front, read through Accessibility: the focused
/// element's selected text, which is what most apps expose. Some do not, and the
/// hotkey falls back to the clipboard for those, so copying still works everywhere.
enum Selection {
    /// What the hotkey found: the text, and where it was looking. The origin is the
    /// app in front whether or not it gave up a selection, since the clipboard the
    /// hotkey falls back to was most likely filled there too.
    struct Read {
        var text: String?
        var origin: Origin?
    }

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

    /// The selection of whatever has keyboard focus and the app it is in. The text is
    /// nil when there is none, the app does not say, or the grant is missing; the page
    /// is the web area the focus sits in, which the browsers expose with the grant.
    static func read() -> Read {
        let front = NSWorkspace.shared.frontmostApplication
        var read = Read(text: nil, origin: front.flatMap(Origin.init(app:)))
        guard isTrusted, let focused = focusedElement() else { return read }
        read.text = attribute(kAXSelectedTextAttribute, of: focused) as? String
        if let origin = read.origin, let page = page(above: focused) {
            read.origin = Origin(app: origin.app, bundle: origin.bundle, page: page)
        }
        return read
    }

    /// The selected text alone, for a caller that has no use for the origin.
    static func text() -> String? { read().text }

    private static func focusedElement() -> AXUIElement? {
        let system = AXUIElementCreateSystemWide()
        guard let focused = attribute(kAXFocusedUIElementAttribute, of: system),
            CFGetTypeID(focused) == AXUIElementGetTypeID()
        else { return nil }
        // Checked by type id above; `as?` cannot see through a CF type from Swift.
        return unsafeDowncast(focused, to: AXUIElement.self)
    }

    /// The web page the focus is in: the nearest `AXWebArea` up the tree, whose URL
    /// and title are the page's own. Nil outside a browser, and for the pages that
    /// give no address, such as a blank tab.
    private static func page(above element: AXUIElement) -> Origin.Page? {
        var current: AXUIElement? = element
        var depth = 0
        while let el = current, depth < Self.maxDepth {
            if attribute(kAXRoleAttribute, of: el) as? String == "AXWebArea" {
                guard let url = attribute(kAXURLAttribute, of: el) as? URL,
                    url.scheme?.hasPrefix("http") == true
                else { return nil }
                let title = (attribute(kAXTitleAttribute, of: el) as? String)?.trimmingCharacters(
                    in: .whitespacesAndNewlines)
                return Origin.Page(url: url, title: title?.isEmpty == false ? title : nil)
            }
            guard let parent = attribute(kAXParentAttribute, of: el),
                CFGetTypeID(parent) == AXUIElementGetTypeID()
            else { return nil }
            current = unsafeDowncast(parent, to: AXUIElement.self)
            depth += 1
        }
        return nil
    }

    /// How far up the tree a web area is looked for: a page's focus is a few levels
    /// under its web area, and a bound keeps a cyclic tree from being walked forever.
    private static let maxDepth = 40

    private static func attribute(_ name: String, of element: AXUIElement) -> CFTypeRef? {
        var value: CFTypeRef?
        guard AXUIElementCopyAttributeValue(element, name as CFString, &value) == .success else {
            return nil
        }
        return value
    }
}
