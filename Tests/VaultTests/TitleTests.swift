import Testing

@testable import Vault

@Suite struct TitleTests {
    @Test func firstHeadingWins() {
        #expect(
            Title.from(text: "---\na: b\n---\n\nintro line\n\n## The Real Title\n", fallback: "f")
                == "The Real Title")
    }
    @Test func firstLineWhenNoHeading() {
        #expect(
            Title.from(text: "\n\nIt's been a fast year. Really.\nmore", fallback: "f")
                == "It's been a fast year. Really.")
    }
    @Test func fallbackWhenEmpty() {
        #expect(Title.from(text: "  \n", fallback: "notes.txt") == "notes.txt")
    }
    @Test func trimsToEighty() {
        let long = String(repeating: "word ", count: 40)
        #expect(Title.from(text: long, fallback: "f").count <= 80)
    }
}

/// `Title.retitle` is the inverse of `Title.from`: whatever line `from` would read as
/// the title is the line `retitle` replaces, so a renamed file reads back its new name.
@Suite struct RetitleTests {
    @Test func theFirstHeadingIsReplacedAtItsOwnLevel() {
        let text = "---\na: b\n---\n\nintro line\n\n## Old\n\nbody\n"
        #expect(
            Title.retitle(text: text, to: "New") == "---\na: b\n---\n\nintro line\n\n## New\n\nbody\n")
    }
    @Test func theFirstLineIsReplacedWhenThereIsNoHeading() {
        #expect(Title.retitle(text: "\n\nOld line\nmore", to: "New") == "\n\nNew\nmore")
    }
    @Test func anEmptyTextBecomesTheTitle() {
        #expect(Title.retitle(text: "  \n", to: "New") == "New\n")
    }
    @Test func theNewTitleReadsBackThroughFrom() {
        let text = "# Old\n\nbody"
        #expect(Title.from(text: Title.retitle(text: text, to: "New"), fallback: "f") == "New")
    }
}
