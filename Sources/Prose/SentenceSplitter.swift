import Foundation

public enum SentenceSplitter {
    /// Tokens whose trailing period does not end a sentence, checked case
    /// insensitively against the word immediately before the period. A single
    /// letter is also guarded, to keep an initial like "J." from splitting.
    /// "no" is ambiguous ("No. 5" vs a sentence ending in "no."), so it only
    /// guards when the next non-space character after it is a digit; that
    /// check is applied separately in `isAbbreviation`, not by membership
    /// alone.
    static let abbreviations: Set<String> = [
        "e.g", "i.e", "etc", "vs", "cf", "dr", "mr", "mrs", "ms", "prof", "st",
        "no", "fig", "vol", "approx", "dept", "inc", "ltd", "jr", "sr",
    ]

    /// Splits each blank-line-separated paragraph into sentences on terminal
    /// punctuation (. ! ?) followed by whitespace, so a heading or a list item
    /// never runs into the line after it, and a paragraph end always closes a
    /// sentence even without terminal punctuation. A period following a known
    /// abbreviation or a single-letter initial does not end a sentence.
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
                if j < paragraph.upperBound, source[j].isWhitespace,
                    !isAbbreviation(before: i, after: j, in: paragraph, of: source)
                {
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

    /// Whether the period at `i` (whitespace follows at `j`) closes a known
    /// abbreviation rather than a sentence.
    static func isAbbreviation(
        before i: String.Index, after j: String.Index, in paragraph: Range<String.Index>, of source: String
    ) -> Bool {
        var lo = i
        while lo > paragraph.lowerBound, !source[source.index(before: lo)].isWhitespace {
            lo = source.index(before: lo)
        }
        let word = source[lo..<i]
        if word.count == 1, word.first?.isLetter == true { return true }
        let lowered = word.lowercased()
        guard abbreviations.contains(lowered) else { return false }
        if lowered == "no" {
            var p = j
            while p < paragraph.upperBound, source[p].isWhitespace { p = source.index(after: p) }
            return p < paragraph.upperBound && source[p].isNumber
        }
        return true
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
