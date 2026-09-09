import Foundation

public enum NoteName {
    public static let maxLength = 60
    static let unsafe = CharacterSet(charactersIn: "/:\\?*\"<>|").union(.controlCharacters).union(
        .newlines)

    public static func make(from text: String, taken: Set<String>) -> String {
        let firstLine =
            text.split(separator: "\n").map { $0.trimmingCharacters(in: .whitespaces) }
            .first { !$0.isEmpty } ?? ""
        var base =
            firstLine.drop(while: { $0 == "#" || $0 == " " })
            .unicodeScalars.filter { !unsafe.contains($0) }
            .map(String.init).joined()
            .trimmingCharacters(in: .whitespaces)
        while base.hasSuffix(".") { base.removeLast() }
        if base.count > maxLength { base = String(base.prefix(maxLength)) }
        if base.isEmpty { base = "Note" }
        var candidate = base + ".md"
        var n = 2
        while taken.contains(candidate) {
            candidate = "\(base) \(n).md"
            n += 1
        }
        return candidate
    }
}
