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
