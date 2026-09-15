import Testing

@testable import Vault

@Suite struct ClipboardPreviewTests {
    @Test func trimsTheTextAndTakesTheTitleFromTheFirstLine() {
        let p = ClipboardPreview(text: "  \n# Fast year\n\nOne two three.\n  ")
        #expect(p?.text == "# Fast year\n\nOne two three.")
        #expect(p?.title == "Fast year")
    }
    @Test func isNilForWhitespace() {
        #expect(ClipboardPreview(text: " \n\t ") == nil)
        #expect(ClipboardPreview(text: "") == nil)
    }
    @Test func countsWordsAndEstimatesAtTheRate() {
        let p = ClipboardPreview(text: String(repeating: "word ", count: 320))!
        #expect(p.words == 320)
        #expect(p.estimate(factor: 1) == .seconds(120))
        #expect(p.estimate(factor: 2) == .seconds(60))
    }
    @Test func titleFallsBackToNoteWhenTheFirstLineIsOnlyHashes() {
        // `Title.from` clips a heading of nothing to an empty string, and the panel
        // must still have a title to show, the same one the file would be named.
        let p = ClipboardPreview(text: "#\n")
        #expect(p?.title == "Note")
    }
}

@Suite struct ClipboardPreviewLabelTests {
    @Test func theLabelIsTheOriginWhenKnownElseTheSource() {
        let notes = Origin(app: "Notes", bundle: "com.apple.Notes")
        #expect(ClipboardPreview(text: "Hi", source: .selection, origin: notes)?.label == "From Notes")
        #expect(ClipboardPreview(text: "Hi", source: .selection)?.label == "From selection")
        #expect(ClipboardPreview(text: "Hi", source: .clipboard)?.label == "From clipboard")
    }
}
