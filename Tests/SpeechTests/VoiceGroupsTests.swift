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
    @Test func regionNameIsHuman() {
        #expect(
            Voice(id: "x", name: "x", language: "en-GB", quality: .standard).regionName
                == "United Kingdom")
    }
}
