import Foundation

public enum SentenceSplitter {
    /// Splits each blank-line-separated paragraph into sentences on terminal
    /// punctuation (. ! ?) followed by whitespace, so a heading or a list item
    /// never runs into the line after it, and a paragraph end always closes a
    /// sentence even without terminal punctuation.
    public static func split(_ source: String) -> [Sentence] {
        var out: [Sentence] = []
        for paragraph in paragraphRanges(in: source) {
            out.append(contentsOf: splitParagraph(paragraph, in: source))
        }
        return out
    }

    static func splitParagraph(_ paragraph: Range<String.Index>, in source: String) -> [Sentence] {
        var out: [Sentence] = []
        var start = paragraph.lowerBound
        var i = paragraph.lowerBound
        while i < paragraph.upperBound {
            let c = source[i]
            if c == "." || c == "!" || c == "?" {
                var j = source.index(after: i)
                while j < paragraph.upperBound, source[j] == "\"" || source[j] == "'" || source[j] == ")" {
                    j = source.index(after: j)
                }
                if j < paragraph.upperBound, source[j].isWhitespace {
                    let trimmed = trim(start..<j, in: source)
                    if !trimmed.isEmpty {
                        out.append(Sentence(text: String(source[trimmed]), range: trimmed))
                    }
                    var k = j
                    while k < paragraph.upperBound, source[k].isWhitespace { k = source.index(after: k) }
                    start = k
                    i = k
                    continue
                }
            }
            i = source.index(after: i)
        }
        let trimmed = trim(start..<paragraph.upperBound, in: source)
        if !trimmed.isEmpty { out.append(Sentence(text: String(source[trimmed]), range: trimmed)) }
        return out
    }

    static func paragraphRanges(in s: String) -> [Range<String.Index>] {
        var ranges: [Range<String.Index>] = []
        var start = s.startIndex
        var i = s.startIndex
        while i < s.endIndex {
            if s[i] == "\n", let next = s.index(i, offsetBy: 1, limitedBy: s.endIndex), next < s.endIndex,
                s[next] == "\n"
            {
                ranges.append(start..<i)
                var j = next
                while j < s.endIndex, s[j] == "\n" { j = s.index(after: j) }
                start = j
                i = j
            } else {
                i = s.index(after: i)
            }
        }
        ranges.append(start..<s.endIndex)
        return ranges.filter { !$0.isEmpty }
    }

    static func trim(_ r: Range<String.Index>, in s: String) -> Range<String.Index> {
        var lo = r.lowerBound
        var hi = r.upperBound
        while lo < hi, s[lo].isWhitespace { lo = s.index(after: lo) }
        while hi > lo, s[s.index(before: hi)].isWhitespace { hi = s.index(before: hi) }
        return lo..<hi
    }
}
