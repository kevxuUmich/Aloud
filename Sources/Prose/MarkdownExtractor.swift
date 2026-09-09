import Foundation
import Markdown

public struct MarkdownExtractor: Extractor {
    public init() {}
    public func script(from data: Data, options: ExtractOptions) throws -> Script {
        let raw = FrontMatter.strip(try data.decodedText())
        let document = Document(parsing: raw, options: .disableSmartOpts)
        var walker = SpeechWalker(skipCode: options.skipCode)
        walker.visit(document)
        let source = Paragraphs.normalize(walker.blocks.joined(separator: "\n\n"))
        return Script(source: source, sentences: SentenceSplitter.split(source))
    }
}

public enum FrontMatter {
    /// Drops a leading YAML block fenced by `---` lines.
    public static func strip(_ text: String) -> String {
        let lines = text.split(separator: "\n", omittingEmptySubsequences: false)
        guard lines.first?.trimmingCharacters(in: .whitespaces) == "---" else { return text }
        guard
            let end = lines.dropFirst().firstIndex(where: {
                $0.trimmingCharacters(in: .whitespaces) == "---"
            })
        else { return text }
        return lines[(end + 1)...].joined(separator: "\n")
    }
}

/// Collects one spoken block per Markdown block; inline structure is flattened to its text.
struct SpeechWalker: MarkupWalker {
    let skipCode: Bool
    var blocks: [String] = []

    mutating func visitHeading(_ heading: Heading) { blocks.append(Inline.text(of: heading)) }
    mutating func visitParagraph(_ paragraph: Paragraph) { blocks.append(Inline.text(of: paragraph)) }
    mutating func visitCodeBlock(_ codeBlock: CodeBlock) {
        blocks.append(skipCode ? "Code block." : codeBlock.code.trimmingCharacters(in: .newlines))
    }
    mutating func visitHTMLBlock(_ html: HTMLBlock) {}
    mutating func visitThematicBreak(_ thematicBreak: ThematicBreak) {}
    mutating func visitListItem(_ listItem: ListItem) {
        // A list item's paragraphs and nested lists are each their own block; the marker is dropped.
        descendInto(listItem)
    }
    mutating func visitTable(_ table: Table) {
        blocks.append(table.head.cells.map(Inline.text(of:)).joined(separator: ", "))
        for row in table.body.rows {
            blocks.append(row.cells.map(Inline.text(of:)).joined(separator: ", "))
        }
    }
}

enum Inline {
    static func text(of markup: Markup) -> String {
        var out = ""
        for child in markup.children { append(child, to: &out) }
        return out
    }
    static func append(_ m: Markup, to out: inout String) {
        switch m {
        case let t as Text: out += t.string
        case let c as InlineCode: out += c.code
        case is SoftBreak, is LineBreak: out += " "
        case is Image, is InlineHTML: break
        default: for child in m.children { append(child, to: &out) }
        }
    }
}
