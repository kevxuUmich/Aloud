import Foundation
import Prose

/// Where a piece of text came from: the app it was selected or copied in, and the web
/// page when it was one. Never a file path - the note is the text, not a link to a
/// place on disk. It is what the card shows an icon for and what a note written from
/// the panel keeps in its front matter, so the icon survives the app's own relaunch.
public struct Origin: Equatable, Hashable, Sendable {
    public struct Page: Equatable, Hashable, Sendable {
        public let url: URL
        /// The page's own title, when the source said. A browser's selection has one;
        /// a copy stamped with a URL alone does not.
        public let title: String?
        public init(url: URL, title: String? = nil) {
            self.url = url
            self.title = title
        }
        /// The site, for the card's line: "google.com" rather than the whole address.
        public var host: String? {
            guard let host = url.host() else { return nil }
            return host.hasPrefix("www.") ? String(host.dropFirst(4)) : host
        }
    }

    /// The app's name as the Finder shows it.
    public let app: String
    public let bundle: String
    public let page: Page?

    public init(app: String, bundle: String, page: Page? = nil) {
        self.app = app
        self.bundle = bundle
        self.page = page
    }

    /// The card's line: the site when there is one, else the app. The icon beside the
    /// line already says which app, and the line is short enough to leave room for the
    /// length after it.
    public var label: String { "From \(page?.host ?? app)" }

    // MARK: Front matter

    /// The block a note carries at its top. Plain keys, so the note reads as one of
    /// Obsidian's own: `source` is the app, `source_id` its bundle, and the page's
    /// address and title follow when there is one.
    public var frontMatter: String {
        var lines = ["---", "source: \(Self.quote(app))", "source_id: \(Self.quote(bundle))"]
        if let page {
            lines.append("source_url: \(Self.quote(page.url.absoluteString))")
            if let title = page.title { lines.append("source_title: \(Self.quote(title))") }
        }
        lines.append("---")
        return lines.joined(separator: "\n") + "\n"
    }

    /// The origin a note's front matter records, or nil when it has none. Only the
    /// leading block is read, and only its own keys; a note with other front matter
    /// is left as the text it was.
    public init?(frontMatterOf text: String) {
        let lines = text.split(separator: "\n", omittingEmptySubsequences: false)
        guard lines.first?.trimmingCharacters(in: .whitespaces) == "---",
            let end = lines.dropFirst().firstIndex(where: {
                $0.trimmingCharacters(in: .whitespaces) == "---"
            })
        else { return nil }
        var fields: [String: String] = [:]
        for line in lines[1..<end] {
            guard let colon = line.firstIndex(of: ":") else { continue }
            let key = line[..<colon].trimmingCharacters(in: .whitespaces)
            fields[key] = Self.unquote(line[line.index(after: colon)...])
        }
        guard let app = fields["source"], !app.isEmpty, let bundle = fields["source_id"],
            !bundle.isEmpty
        else { return nil }
        let page = fields["source_url"].flatMap(URL.init(string:)).map {
            Page(url: $0, title: fields["source_title"].flatMap { $0.isEmpty ? nil : $0 })
        }
        self.init(app: app, bundle: bundle, page: page)
    }

    /// Double-quoted, so a title with a colon or a hash in it is still one value.
    static func quote(_ s: String) -> String {
        let escaped = s.replacingOccurrences(of: "\\", with: "\\\\")
            .replacingOccurrences(of: "\"", with: "\\\"")
        return "\"\(escaped)\""
    }

    static func unquote(_ s: Substring) -> String {
        let t = s.trimmingCharacters(in: .whitespaces)
        guard t.count >= 2, t.hasPrefix("\""), t.hasSuffix("\"") else { return t }
        var out = ""
        var escaped = false
        for c in t.dropFirst().dropLast() {
            if escaped {
                out.append(c)
                escaped = false
            } else if c == "\\" {
                escaped = true
            } else {
                out.append(c)
            }
        }
        return out
    }
}
