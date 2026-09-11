import Foundation
import Prose

public enum Title {
    public static let maxLength = 80
    public static func from(text: String, fallback: String) -> String {
        let body = FrontMatter.strip(text)
        let lines = body.split(separator: "\n").map { $0.trimmingCharacters(in: .whitespaces) }
            .filter { !$0.isEmpty }
        if let heading = lines.first(where: { $0.hasPrefix("#") }) {
            return clip(heading.drop(while: { $0 == "#" || $0 == " " }))
        }
        if let first = lines.first { return clip(Substring(first)) }
        return fallback
    }
    /// The text with its title line replaced: the first heading, at its own level, or
    /// the first non-empty line when there is none, in the body after any front matter.
    /// An empty body has no line to replace, so the title becomes the body. It is the
    /// mirror of `from`, so what a rename writes is what the scanner reads back.
    public static func retitle(text: String, to title: String) -> String {
        let clean = title.trimmingCharacters(in: .whitespacesAndNewlines)
        let frontMatterEnd = text.count - FrontMatter.strip(text).count
        let head = text.prefix(frontMatterEnd)
        var lines = text.dropFirst(frontMatterEnd).split(
            separator: "\n", omittingEmptySubsequences: false
        ).map(String.init)
        let nonEmpty = lines.indices.filter {
            !lines[$0].trimmingCharacters(in: .whitespaces).isEmpty
        }
        if let h = nonEmpty.first(where: { lines[$0].trimmingCharacters(in: .whitespaces).hasPrefix("#") }) {
            let hashes = lines[h].trimmingCharacters(in: .whitespaces).prefix { $0 == "#" }
            lines[h] = hashes + " " + clean
        } else if let first = nonEmpty.first {
            lines[first] = clean
        } else {
            return head + clean + "\n"
        }
        return head + lines.joined(separator: "\n")
    }

    static func clip(_ s: Substring) -> String {
        let t = String(s).trimmingCharacters(in: .whitespaces)
        return t.count <= maxLength ? t : String(t.prefix(maxLength - 1)) + "…"
    }
}
