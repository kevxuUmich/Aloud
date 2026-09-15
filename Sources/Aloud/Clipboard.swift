import AppKit
import Vault

/// The clipboard, and where what is on it came from. macOS keeps no record of the app
/// that copied, so the origin is pieced together from what the copy left behind: the
/// stamp some apps put on it, the page address the browsers add, and failing those the
/// app that was in front when the clipboard last changed, which the watcher notes as
/// clipboard managers do. A copy made in the last moment, before the watcher saw it,
/// is credited to the app in front now, which is where the hotkey was pressed.
@MainActor final class Clipboard {
    struct Read: Equatable {
        /// Nil when there is no text, and for a concealed copy: a password manager
        /// marks what it copies so that no one reads it back, and Aloud would read it
        /// out loud.
        var text: String?
        var origin: Origin?
        var concealed = false
    }

    /// The nspasteboard.org convention, which the password managers and the clipboard
    /// managers follow: a copy that must not be kept, and the bundle that made one.
    static let concealedType = NSPasteboard.PasteboardType("org.nspasteboard.ConcealedType")
    static let sourceType = NSPasteboard.PasteboardType("org.nspasteboard.source")
    /// Chromium's stamp: the page a copy was made on, which Chrome, Brave, Edge and
    /// Arc all leave.
    static let chromiumURLType = NSPasteboard.PasteboardType("org.chromium.source-url")
    /// Safari's copy of a selection is a web archive whose main resource is the page.
    static let webArchiveType = NSPasteboard.PasteboardType("com.apple.webarchive")

    private let pasteboard: NSPasteboard
    private let front: () -> Origin?
    /// The clipboard's change count the watcher last saw, and the app in front then.
    private var seen: (count: Int, app: Origin?)?
    private var timer: Timer?

    /// `front` is asked which app is in front, at each change and at each read; a test
    /// hands in its own answer, since the app in front of a test is whatever it is.
    init(
        pasteboard: NSPasteboard = .general,
        front: @escaping () -> Origin? = {
            NSWorkspace.shared.frontmostApplication.flatMap(Origin.init(app:))
        }
    ) {
        self.pasteboard = pasteboard
        self.front = front
    }

    /// Starts noting the app in front each time the clipboard changes. A change count
    /// is one integer read from the pasteboard server, so the interval is cheap; it is
    /// short so a copy is credited to the app it was made in, not the app switched to.
    func watch(every interval: Duration = .seconds(1)) {
        timer?.invalidate()
        tick()
        let seconds = Double(interval.components.seconds) + Double(interval.components.attoseconds) / 1e18
        let timer = Timer(timeInterval: seconds, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated { self?.tick() }
        }
        RunLoop.main.add(timer, forMode: .common)
        self.timer = timer
    }

    func stop() {
        timer?.invalidate()
        timer = nil
    }

    /// What the watcher does on its interval, and what a test calls in its place. The
    /// first tick credits no one: whatever was on the clipboard was copied before
    /// Aloud was looking, and the app in front at launch is likely Aloud itself.
    func tick() {
        let count = pasteboard.changeCount
        guard let seen else {
            self.seen = (count, nil)
            return
        }
        guard seen.count != count else { return }
        self.seen = (count, Self.notAloud(front()))
    }

    /// Aloud is never where text came from: with its own window in front, the copy
    /// was made somewhere it cannot see, and the card says "From clipboard".
    private static func notAloud(_ origin: Origin?) -> Origin? {
        origin?.bundle == ownBundle ? nil : origin
    }

    /// Aloud's own bundle, spelled out for the test runner, which has none.
    static let ownBundle = Bundle.main.bundleIdentifier ?? "design.kevxu.aloud"

    /// The clipboard now: its text and its origin, the best of what the copy says
    /// about itself, what the watcher saw, and the app in front.
    func read() -> Read {
        let types = Set(pasteboard.types ?? [])
        if types.contains(Self.concealedType) { return Read(text: nil, origin: nil, concealed: true) }
        let text = pasteboard.string(forType: .string)
        let stamped = pasteboard.string(forType: Self.sourceType).flatMap(Origin.init(bundle:))
        let watched = seen?.count == pasteboard.changeCount ? seen?.app : nil
        guard let app = stamped ?? watched ?? Self.notAloud(front()) else { return Read(text: text) }
        let page = pageURL(in: types).map { Origin.Page(url: $0) }
        return Read(text: text, origin: Origin(app: app.app, bundle: app.bundle, page: page))
    }

    /// The page a copy was made on, when the browser said. Only a web address counts:
    /// a file the browser had open is a path, and the origin never carries one.
    private func pageURL(in types: Set<NSPasteboard.PasteboardType>) -> URL? {
        var url: URL?
        if types.contains(Self.chromiumURLType) {
            url = pasteboard.string(forType: Self.chromiumURLType).flatMap(URL.init(string:))
        } else if types.contains(Self.webArchiveType),
            let data = pasteboard.data(forType: Self.webArchiveType),
            let plist = try? PropertyListSerialization.propertyList(from: data, format: nil)
                as? [String: Any],
            let main = plist["WebMainResource"] as? [String: Any],
            let string = main["WebResourceURL"] as? String
        {
            url = URL(string: string)
        }
        guard let url, url.scheme?.hasPrefix("http") == true else { return nil }
        return url
    }
}
