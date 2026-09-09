import Foundation

/// Where a sentence went after the file changed underneath the reader.
public enum ScriptAnchor {
    public static func index(of sentenceText: String, near index: Int, in script: Script) -> Int {
        let matches = script.sentences.indices.filter { script.sentences[$0].text == sentenceText }
        if let best = matches.min(by: { abs($0 - index) < abs($1 - index) }) { return best }
        return max(0, min(index, script.sentences.count - 1))
    }
}
