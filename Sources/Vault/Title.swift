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
    static func clip(_ s: Substring) -> String {
        let t = String(s).trimmingCharacters(in: .whitespaces)
        return t.count <= maxLength ? t : String(t.prefix(maxLength - 1)) + "…"
    }
}
