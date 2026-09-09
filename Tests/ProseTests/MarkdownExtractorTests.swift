import Foundation
import Testing

@testable import Prose

@Suite struct MarkdownExtractorTests {
    func fixture(_ name: String) throws -> Data {
        try Data(
            contentsOf: Bundle.module.url(forResource: name, withExtension: nil, subdirectory: "Fixtures")!)
    }
    @Test func readsTheEssayAsProse() throws {
        let s = try MarkdownExtractor().script(from: fixture("essay.md"), options: .default)
        #expect(
            s.source
                == """
                Pick your own problems

                Nobody really teaches you research. See Hamming's talk for more.

                first item

                second item with inline code

                Code block.

                Name, Country

                Samantha, United States

                Karen, Australia

                A quoted line.

                Final paragraph.
                """)
    }
    @Test func frontMatterIsDropped() throws {
        let s = try MarkdownExtractor().script(from: fixture("essay.md"), options: .default)
        #expect(!s.source.contains("tags:"))
    }
    @Test func codeIsReadWhenNotSkipped() throws {
        let s = try MarkdownExtractor().script(
            from: fixture("essay.md"), options: ExtractOptions(skipCode: false))
        #expect(s.source.contains("let x = 1"))
        #expect(!s.source.contains("Code block."))
    }
    @Test func headingIsItsOwnSentence() throws {
        let s = try MarkdownExtractor().script(from: fixture("essay.md"), options: .default)
        #expect(s.sentences.first?.text == "Pick your own problems")
        for sen in s.sentences { #expect(String(s.source[sen.range]) == sen.text) }
    }
    @Test func hardWrappedParagraphJoins() throws {
        let md = "one line\nsecond line of the same paragraph\n\nnext"
        let s = try MarkdownExtractor().script(from: Data(md.utf8), options: .default)
        #expect(s.source == "one line second line of the same paragraph\n\nnext")
    }
}
