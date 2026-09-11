import Foundation

public enum NoteName {
    public static let maxLength = 60
    static let unsafe = CharacterSet(charactersIn: "/:\\?*\"<>|").union(.controlCharacters).union(
        .newlines)

    /// The one safe filename a title makes, with the given extension: the characters
    /// a filesystem refuses are dropped, trailing dots go, and the length is capped.
    public static func fileName(for title: String, extension ext: String) -> String {
        var base =
            title.drop(while: { $0 == "#" || $0 == " " })
            .unicodeScalars.filter { !unsafe.contains($0) }
            .map(String.init).joined()
            .trimmingCharacters(in: .whitespaces)
        while base.hasSuffix(".") { base.removeLast() }
        if base.count > maxLength { base = String(base.prefix(maxLength)) }
        if base.isEmpty { base = "Note" }
        return ext.isEmpty ? base : base + "." + ext
    }

    /// The names, among those taken, that a note of this text would have been given:
    /// the title's own name and its numbered siblings, in the order they were handed
    /// out, so a caller can look for the text there and nowhere else.
    public static func siblings(of text: String, among taken: Set<String>) -> [String] {
        let base = base(for: text)
        var names: [String] = []
        var candidate = base + ".md"
        var n = 2
        while taken.contains(candidate) {
            names.append(candidate)
            candidate = "\(base) \(n).md"
            n += 1
        }
        return names
    }

    /// The name without its extension or number: the first non-blank line, made safe.
    private static func base(for text: String) -> String {
        let firstLine =
            text.split(separator: "\n").map { $0.trimmingCharacters(in: .whitespaces) }
            .first { !$0.isEmpty } ?? ""
        return fileName(for: firstLine, extension: "")
    }

    public static func make(from text: String, taken: Set<String>) -> String {
        let base = base(for: text)
        var candidate = base + ".md"
        var n = 2
        while taken.contains(candidate) {
            candidate = "\(base) \(n).md"
            n += 1
        }
        return candidate
    }
}
