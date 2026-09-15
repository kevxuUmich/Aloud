import Foundation
import Testing

@testable import Vault

@Suite struct OriginTests {
    let brave = Origin(
        app: "Brave Browser", bundle: "com.brave.Browser",
        page: .init(
            url: URL(string: "https://www.google.com/search?q=kokoro")!,
            title: "kokoro: \"usage\" - Google Search"))

    @Test func theLabelIsTheSiteElseTheApp() {
        #expect(brave.label == "From google.com")
        #expect(Origin(app: "Notes", bundle: "com.apple.Notes").label == "From Notes")
    }

    @Test func frontMatterRoundTripsWithColonsAndQuotesInTheTitle() {
        let text = brave.frontMatter + "# Body\n\nText."
        #expect(Origin(frontMatterOf: text) == brave)
        #expect(
            brave.frontMatter == """
                ---
                source: "Brave Browser"
                source_id: "com.brave.Browser"
                source_url: "https://www.google.com/search?q=kokoro"
                source_title: "kokoro: \\"usage\\" - Google Search"
                ---

                """)
    }

    @Test func anAppAloneRoundTrips() {
        let notes = Origin(app: "Notes", bundle: "com.apple.Notes")
        #expect(Origin(frontMatterOf: notes.frontMatter + "Body") == notes)
        #expect(Origin(frontMatterOf: notes.frontMatter + "Body")?.page == nil)
    }

    @Test func bareValuesAreReadToo() {
        let text = "---\nsource: Notes\nsource_id: com.apple.Notes\ntags: [a, b]\n---\nBody"
        #expect(Origin(frontMatterOf: text) == Origin(app: "Notes", bundle: "com.apple.Notes"))
    }

    @Test func otherFrontMatterAndNoFrontMatterAreNil() {
        #expect(Origin(frontMatterOf: "---\ntitle: x\n---\nBody") == nil)
        #expect(Origin(frontMatterOf: "# Just a note") == nil)
        #expect(Origin(frontMatterOf: "---\nsource: Notes\n---\nBody") == nil)
    }
}
