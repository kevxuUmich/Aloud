import Testing

@testable import Prose

@Suite struct ScriptAnchorTests {
    func script(_ s: String) -> Script { Script(source: s, sentences: SentenceSplitter.split(s)) }

    @Test func findsTheSameSentenceAfterAnInsert() {
        let new = script("Added first. One two. Three four. Five six.")
        #expect(ScriptAnchor.index(of: "Three four.", near: 1, in: new) == 2)
    }

    @Test func prefersTheNearestOfDuplicates() {
        let new = script("Same. Other. Same. Same.")
        #expect(ScriptAnchor.index(of: "Same.", near: 3, in: new) == 3)
    }

    @Test func fallsBackToTheClampedIndex() {
        let new = script("Only one.")
        #expect(ScriptAnchor.index(of: "gone.", near: 5, in: new) == 0)
    }
}
