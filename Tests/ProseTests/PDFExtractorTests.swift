import Foundation
import Testing

@testable import Prose

@Suite struct PDFExtractorTests {
    @Test func readsPagesInOrder() throws {
        let pdf = TestPDF.make(pages: [["first sentence.", "second sentence."], ["third sentence."]])
        let s = try PDFExtractor().script(from: pdf, options: .default)
        #expect(s.sentences.map(\.text) == ["first sentence.", "second sentence.", "third sentence."])
    }

    @Test func joinsHyphenatedLineBreaks() {
        let out = PDFCleanup.clean(pages: ["the exper-\niment worked."])
        #expect(out == "the experiment worked.")
    }

    @Test func dropsLinesRepeatedOnMostPages() {
        let out = PDFCleanup.clean(pages: [
            "Journal of Things\nbody one.", "Journal of Things\nbody two.", "Journal of Things\nbody three.",
        ])
        #expect(!out.contains("Journal of Things"))
        #expect(out.contains("body one."))
    }

    /// Two pages are too few to tell a running header from a line the prose repeats,
    /// so nothing is dropped from one; three is where the rule starts.
    @Test func keepsALineSharedByATwoPageDocument() {
        let out = PDFCleanup.clean(pages: [
            "Chapter One\nbody one.", "Chapter One\nbody two.",
        ])
        #expect(out.contains("Chapter One"))
    }

    @Test func keepsALineRepeatedOnHalfOrFewerPages() {
        let out = PDFCleanup.clean(pages: ["Intro\nbody.", "Intro\nbody.", "other\nbody.", "other\nbody."])
        #expect(out.contains("Intro"))
    }

    @Test func dropsBarePageNumbers() {
        let out = PDFCleanup.clean(pages: ["body.\n12", "more.\n13"])
        #expect(!out.contains("12"))
        #expect(!out.contains("13"))
    }

    @Test func collapsesSingleLineBreaksInsideAParagraph() {
        let out = Paragraphs.normalize(
            PDFCleanup.clean(pages: ["one line\nsame paragraph.\n\nnext paragraph."]))
        #expect(out == "one line same paragraph.\n\nnext paragraph.")
    }

    @Test func imageOnlyPDFIsEmpty() throws {
        let pdf = TestPDF.make(pages: [[]])
        let s = try PDFExtractor().script(from: pdf, options: .default)
        #expect(s.sentences.isEmpty)
    }

    @Test func encryptedPDFIsEmpty() throws {
        let pdf = TestPDF.makeEncrypted(pages: [["first sentence."]])
        let s = try PDFExtractor().script(from: pdf, options: .default)
        #expect(s.sentences.isEmpty)
    }

    @Test func garbageIsUndecodable() {
        #expect(throws: ExtractError.self) {
            try PDFExtractor().script(from: Data([1, 2, 3]), options: .default)
        }
    }

    @Test func registryKnowsPDF() throws { _ = try Extractors.extractor(for: .pdf) }
}
