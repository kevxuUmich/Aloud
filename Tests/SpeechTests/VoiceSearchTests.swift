import Foundation
import Testing

@testable import Speech

@Suite struct VoiceSearchTests {
    let voices = [
        Voice(id: "1", name: "Samantha", language: "en-US", quality: .enhanced),
        Voice(id: "2", name: "Daniel", language: "en-GB", quality: .premium),
        Voice(id: "3", name: "Majed", language: "ar-001", quality: .standard),
        Voice(id: "4", name: "Aaron", language: "en-US", quality: .standard),
    ]
    var groups: [VoiceGroup] { VoiceGroups.group(voices, currentLanguage: "en-US") }

    func names(_ g: [VoiceGroup]) -> [String] { g.flatMap { $0.voices.map(\.name) } }

    @Test func matchesAVoiceByName() {
        #expect(names(VoiceSearch.filter(groups, query: "sam")) == ["Samantha"])
    }
    /// The group's name is the language in the reader's own words, and it is the only
    /// place the word "English" is written, so a search for it has to reach the rows.
    @Test func matchesAGroupByItsLanguageName() {
        let hit = VoiceSearch.filter(groups, query: "english")
        #expect(hit.count == 1)
        #expect(names(hit) == ["Daniel", "Samantha", "Aaron"])
    }
    @Test func matchesAVoiceByItsRegion() {
        #expect(names(VoiceSearch.filter(groups, query: "United Kingdom")) == ["Daniel"])
    }
    @Test func matchesAVoiceByItsQualityLabel() {
        #expect(names(VoiceSearch.filter(groups, query: "premium")) == ["Daniel"])
    }
    /// Nothing typed is not a filter that matches nothing; it is no filter at all.
    @Test func anEmptyQueryReturnsEverything() {
        #expect(VoiceSearch.filter(groups, query: "") == groups)
        #expect(VoiceSearch.filter(groups, query: "   ") == groups)
    }
    @Test func noMatchesLeavesNoGroups() {
        #expect(VoiceSearch.filter(groups, query: "zzzz").isEmpty)
    }
}
