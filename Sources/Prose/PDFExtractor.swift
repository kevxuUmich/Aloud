import Foundation
import PDFKit

public struct PDFExtractor: Extractor {
    public init() {}
    public func script(from data: Data, options: ExtractOptions) throws -> Script {
        guard let doc = PDFDocument(data: data) else { throw ExtractError.undecodable }
        var pages: [String] = []
        for i in 0..<doc.pageCount { pages.append(doc.page(at: i)?.string ?? "") }
        let source = Paragraphs.normalize(PDFCleanup.clean(pages: pages))
        return Script(source: source, sentences: SentenceSplitter.split(source))
    }
}

/// The layout noise PDFKit hands back with the text: running headers and footers,
/// page numbers, hyphenation at line ends, and one line break per printed line.
enum PDFCleanup {
    static func clean(pages: [String]) -> String {
        let pageLines = pages.map { page in
            page.components(separatedBy: .newlines).map { $0.trimmingCharacters(in: .whitespaces) }
        }
        let repeated = repeatedLines(pageLines)
        var out: [String] = []
        for lines in pageLines {
            var kept: [String] = []
            for line in lines {
                if repeated.contains(line) { continue }
                if isBarePageNumber(line) { continue }
                kept.append(line)
            }
            out.append(joinHyphens(kept).joined(separator: "\n"))
        }
        return out.filter { !$0.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }
            .joined(separator: "\n\n")
    }

    /// A non-empty line that appears on more than half the pages is a running header or footer.
    static func repeatedLines(_ pages: [[String]]) -> Set<String> {
        guard pages.count > 1 else { return [] }
        var counts: [String: Int] = [:]
        for lines in pages {
            for line in Set(lines) where !line.isEmpty { counts[line, default: 0] += 1 }
        }
        return Set(counts.filter { $0.value * 2 > pages.count }.keys)
    }

    static func isBarePageNumber(_ line: String) -> Bool {
        !line.isEmpty && line.allSatisfy(\.isNumber) && line.count <= 4
    }

    /// "exper-" + "iment" -> "experiment"; the split word is rejoined on the first line.
    static func joinHyphens(_ lines: [String]) -> [String] {
        var out: [String] = []
        var carry = ""
        for line in lines {
            let joined = carry + line
            carry = ""
            if joined.hasSuffix("-"), joined.count > 1,
                joined[joined.index(before: joined.index(before: joined.endIndex))].isLetter
            {
                carry = String(joined.dropLast())
            } else {
                out.append(joined)
            }
        }
        if !carry.isEmpty { out.append(carry) }
        return out
    }
}
