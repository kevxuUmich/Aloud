import Foundation
import Testing

@Suite struct LiteralLintTests {
    static let root = URL(fileURLWithPath: #filePath)
        .deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()

    static let patterns: [String] = [
        #"\.padding\(\s*\d"#,
        #"\.padding\(\.[a-zA-Z]+,\s*\d"#,
        #"spacing:\s*\d"#,
        #"(minimum|maximum|minLength|width|height|minWidth|maxWidth|minHeight|maxHeight):\s*\d"#,
        #"cornerRadius:\s*\d"#,
        #"\.font\(\.system\(size"#,
        #"Color\((red|\.sRGB|white|hue)"#,
        #"\.opacity\(\s*0?\.\d"#,
        #"duration:\s*\d"#,
        #"lineWidth:\s*\d"#,
        #"lineLimit\(\s*\d"#,
        #"Color\.(red|blue|green|orange|yellow|purple|pink|gray|white|black)\b"#,
    ]

    static func swiftFiles(under dir: String) -> [URL] {
        let base = root.appendingPathComponent(dir)
        let e = FileManager.default.enumerator(at: base, includingPropertiesForKeys: nil)!
        return e.compactMap { $0 as? URL }.filter { $0.pathExtension == "swift" }
            .filter { $0.lastPathComponent != "Tokens.swift" }
    }

    @Test func noLiteralsOutsideTokens() throws {
        var hits: [String] = []
        for dir in ["Sources/AloudUI", "Sources/Aloud"] {
            for file in Self.swiftFiles(under: dir) {
                let text = try String(contentsOf: file, encoding: .utf8)
                for (n, line) in text.split(separator: "\n", omittingEmptySubsequences: false).enumerated() {
                    for p in Self.patterns where line.range(of: p, options: .regularExpression) != nil {
                        hits.append(
                            "\(file.lastPathComponent):\(n + 1): \(line.trimmingCharacters(in: .whitespaces))"
                        )
                    }
                }
            }
        }
        #expect(hits.isEmpty, "literals outside Tokens.swift:\n\(hits.joined(separator: "\n"))")
    }
}
