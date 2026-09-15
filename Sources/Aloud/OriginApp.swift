import AppKit
import Vault

extension Origin {
    /// The app as a running process names itself. Nil for a process with no bundle,
    /// which has no icon to show either.
    init?(app: NSRunningApplication) {
        guard let bundle = app.bundleIdentifier else { return nil }
        self.init(app: app.localizedName ?? bundle, bundle: bundle)
    }

    /// The app behind a bundle identifier, running or on disk, by the name the Finder
    /// shows. Nil when there is no such app on this Mac.
    init?(bundle: String) {
        if let running = NSRunningApplication.runningApplications(withBundleIdentifier: bundle).first,
            let origin = Origin(app: running)
        {
            self = origin
            return
        }
        guard let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: bundle) else {
            return nil
        }
        let name = FileManager.default.displayName(atPath: url.path)
        self.init(app: (name as NSString).deletingPathExtension, bundle: bundle)
    }
}

/// The icon of the app an origin names, as the Finder draws it. Looked up once per
/// bundle and kept: the card and the bar ask on every redraw, and the workspace's
/// lookup walks Launch Services each time.
@MainActor enum OriginIcon {
    private static var cache: [String: NSImage?] = [:]

    /// Nil when the app is no longer on this Mac, in which case the card keeps its own
    /// mark and the bar its picture of the text.
    static func image(for origin: Origin?) -> NSImage? {
        guard let bundle = origin?.bundle else { return nil }
        if let cached = cache[bundle] { return cached }
        let icon = NSWorkspace.shared.urlForApplication(withBundleIdentifier: bundle).map {
            NSWorkspace.shared.icon(forFile: $0.path)
        }
        cache[bundle] = icon
        return icon
    }
}
