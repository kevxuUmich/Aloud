import Foundation
import Testing

@testable import Prose

@Suite struct PlainTextExtractorTests {
    func fixture(_ name: String) throws -> Data {
        try Data(
            contentsOf: Bundle.module.url(forResource: name, withExtension: nil, subdirectory: "Fixtures")!)
    }
    @Test func joinsLinesInsideAParagraph() throws {
        let s = try PlainTextExtractor().script(from: fixture("plain.txt"), options: .default)
        #expect(
            s.source
                == "nobody really teaches you research. you get a desk. this line continues the paragraph.\n\npick your own problems"
        )
        #expect(
            s.sentences.map(\.text) == [
                "nobody really teaches you research.", "you get a desk.",
                "this line continues the paragraph.", "pick your own problems",
            ])
    }
    @Test func rejectsNonUTF8() {
        #expect(throws: ExtractError.self) {
            try PlainTextExtractor().script(from: Data([0xFF, 0xFE, 0x00]), options: .default)
        }
    }
    @Test func registryKnowsKinds() throws {
        _ = try Extractors.extractor(for: .plainText)
        #expect(throws: ExtractError.self) { try Extractors.extractor(for: .pdf) }
    }
}
