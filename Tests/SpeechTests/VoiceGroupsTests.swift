import Foundation
import Testing

@testable import Speech

@Suite struct VoiceGroupsTests {
    let voices = [
        Voice(id: "1", name: "Samantha", language: "en-US", quality: .enhanced),
        Voice(id: "2", name: "Daniel", language: "en-GB", quality: .premium),
        Voice(id: "3", name: "Majed", language: "ar-001", quality: .standard),
        Voice(id: "4", name: "Aaron", language: "en-US", quality: .standard),
    ]
    @Test func currentLanguageComesFirstAndQualityLeads() {
        let g = VoiceGroups.group(voices, currentLanguage: "en-US")
        #expect(g.first?.language == "en")
        #expect(g.first?.voices.map(\.name) == ["Daniel", "Samantha", "Aaron"])
        #expect(g.map(\.language) == ["en", "ar"])
    }
    /// The tag the pickers sort by has to be BCP-47: `Locale.current.identifier` is
    /// underscored, and its language part would then be the whole "en_US", which
    /// matches no group and sorts the reader's own language wherever the alphabet puts
    /// it.
    @Test func currentLanguageIsABCP47Tag() {
        let code = VoiceGroups.code(VoiceGroups.currentLanguage)
        #expect(!code.contains("_"))
        #expect(code == Locale.current.language.languageCode?.identifier ?? "")
    }
    @Test func regionNameIsHuman() {
        #expect(
            Voice(id: "x", name: "x", language: "en-GB", quality: .standard).regionName
                == "United Kingdom")
    }
    /// "001" is the world region, which the locale does name; a bare language tag has
    /// no region at all and must not invent one.
    @Test func regionNameForWorld() {
        #expect(Voice(id: "x", name: "x", language: "ar-001", quality: .standard).regionName != nil)
        #expect(Voice(id: "y", name: "y", language: "en", quality: .standard).regionName == nil)
    }
}
