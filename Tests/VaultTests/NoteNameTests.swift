import Testing

@testable import Vault

@Suite struct NoteNameTests {
    @Test func firstLineBecomesTheName() {
        #expect(
            NoteName.make(from: "# It's been a fast year.\n\nbody", taken: [])
                == "It's been a fast year.md")
    }
    @Test func unsafeCharactersDrop() {
        #expect(NoteName.make(from: "a/b:c\\d?e*f", taken: []) == "abcdef.md")
    }
    @Test func clipsToSixty() {
        let name = NoteName.make(from: String(repeating: "x", count: 100), taken: [])
        #expect(name.count == 60 + 3)
    }
    @Test func collisionsCount() {
        #expect(NoteName.make(from: "Note", taken: ["Note.md", "Note 2.md"]) == "Note 3.md")
    }
    @Test func emptyIsNote() {
        #expect(NoteName.make(from: " \n ", taken: []) == "Note.md")
    }
}
