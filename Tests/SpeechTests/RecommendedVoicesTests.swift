import Foundation
import Testing

@testable import Speech

@Suite struct RecommendedVoicesTests {
    @Test func bareNameDropsTheBracketedQuality() {
        #expect(Voice.bareName("Jamie (Enhanced)") == "Jamie")
        #expect(Voice.bareName("Zoe (Premium)") == "Zoe")
        #expect(Voice.bareName("Samantha") == "Samantha")
        #expect(Voice.bareName("Eddy (English (UK))") == "Eddy (English (UK))")
        #expect(Voice.bareName("Grandma (Enhanced) x") == "Grandma (Enhanced) x")
    }

    /// Jamie's identifier still says Malcolm, and the system labels the voice with its
    /// quality in brackets; neither is what the list matches on.
    @Test func resolveFindsInstalledByNameLanguageAndQuality() {
        let installed = [
            Voice(
                id: "com.apple.voice.enhanced.en-GB.Malcolm", name: "Jamie (Enhanced)",
                language: "en-GB", quality: .enhanced),
            Voice(id: "zoe-premium", name: "Zoe (Premium)", language: "en-US", quality: .premium),
            Voice(id: "kate-standard", name: "Kate", language: "en-GB", quality: .standard),
            Voice(id: "samantha", name: "Samantha", language: "en-US", quality: .standard),
        ]
        let entries = RecommendedVoices.resolve(installed)
        #expect(entries.map(\.recommendation.name) == RecommendedVoices.all.map(\.name))
        #expect(entries[0].voice?.id == "com.apple.voice.enhanced.en-GB.Malcolm")
        // Zoe is installed at the wrong quality, Kate at the standard one: neither is
        // the voice recommended, so both still want a download.
        #expect(entries.first { $0.recommendation.name == "Zoe" }?.isInstalled == false)
        #expect(entries.first { $0.recommendation.name == "Kate" }?.isInstalled == false)
        #expect(RecommendedVoices.anyInstalled(installed))
        #expect(!RecommendedVoices.anyInstalled([installed[3]]))
    }

    @Test func everyEntryIsDistinctAndSized() {
        #expect(Set(RecommendedVoices.all.map(\.id)).count == RecommendedVoices.all.count)
        #expect(RecommendedVoices.all.allSatisfy { $0.downloadMB > 0 })
        #expect(RecommendedVoices.all[0].sizeLabel == "116 MB")
    }
}
