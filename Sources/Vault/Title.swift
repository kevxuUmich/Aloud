import Foundation

public enum Title {
    public static let maxLength = 80
    public static func from(text: String, fallback: String) -> String {
        let body = stripFrontMatter(text)
        let lines = body.split(separator: "\n").map { $0.trimmingCharacters(in: .whitespaces) }
            .filter { !$0.isEmpty }
        if let heading = lines.first(where: { $0.hasPrefix("#") }) {
            return clip(heading.drop(while: { $0 == "#" || $0 == " " }))
        }
        if let first = lines.first { return clip(Substring(first)) }
        return fallback
    }
    static func clip(_ s: Substring) -> String {
        let t = String(s).trimmingCharacters(in: .whitespaces)
        return t.count <= maxLength ? t : String(t.prefix(maxLength - 1)) + "…"
    }
    static func stripFrontMatter(_ text: String) -> String {
        let lines = text.split(separator: "\n", omittingEmptySubsequences: false)
        guard lines.first?.trimmingCharacters(in: .whitespaces) == "---",
            let end = lines.dropFirst().firstIndex(where: {
                $0.trimmingCharacters(in: .whitespaces) == "---"
            })
        else { return text }
        return lines[(end + 1)...].joined(separator: "\n")
    }
}
