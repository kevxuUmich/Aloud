import Foundation
import Speech
import Testing

@testable import Kokoro

@Suite struct KokoroCatalogueTests {
    /// The seven voices, in the spec's order, each under the prefix so no id can meet
    /// an Apple identifier.
    @Test func theSevenVoicesInOrder() {
        #expect(
            KokoroCatalogue.voices.map(\.id) == [
                "kokoro.af_bella", "kokoro.af_sarah", "kokoro.am_michael", "kokoro.am_fenrir",
                "kokoro.bf_emma", "kokoro.bm_george", "kokoro.bm_fable",
            ])
        #expect(
            KokoroCatalogue.voices.map(\.name) == [
                "Bella", "Sarah", "Michael", "Fenrir", "Emma", "George", "Fable",
            ])
        #expect(KokoroCatalogue.voices.prefix(4).allSatisfy { $0.language == "en-US" && !$0.british })
        #expect(KokoroCatalogue.voices.suffix(3).allSatisfy { $0.language == "en-GB" && $0.british })
        #expect(KokoroCatalogue.speechVoices.allSatisfy { $0.quality == .premium })
    }

    @Test func idsRoundTrip() {
        #expect(KokoroCatalogue.isKokoro("kokoro.af_bella"))
        #expect(!KokoroCatalogue.isKokoro("com.apple.voice.premium.en-US.Zoe"))
        #expect(KokoroCatalogue.voice(for: "kokoro.bm_fable")?.kokoroID == "bm_fable")
        #expect(KokoroCatalogue.voice(for: "kokoro.zz_nobody") == nil)
        #expect(KokoroCatalogue.voice(for: "af_bella") == nil)
    }

    /// Grouped by region for the picker: American first, as the catalogue lists them.
    @Test func regionsFollowTheCatalogue() {
        let regions = KokoroCatalogue.regions
        #expect(regions.map(\.name) == ["United States", "United Kingdom"])
        #expect(regions[0].voices.map(\.name) == ["Bella", "Sarah", "Michael", "Fenrir"])
        #expect(regions[1].voices.map(\.name) == ["Emma", "George", "Fable"])
    }

    @Test func theReleaseIsPinned() {
        let r = KokoroRelease.current
        #expect(
            r.url.absoluteString
                == "https://github.com/kevxuUmich/Aloud/releases/download/kokoro-models/kokoro-1.aar")
        #expect(r.version == "1")
        #expect(r.sha256.count == 64 && r.sha256 == r.sha256.lowercased())
        #expect(r.bytes > 100_000_000)
        #expect(r.sizeLabel.hasSuffix(" MB"))
    }

    @Test func pathsHangOffTheTwoRoots() {
        let p = KokoroPaths(support: URL(fileURLWithPath: "/s"), caches: URL(fileURLWithPath: "/c"))
        #expect(p.modelDirectory(version: "1").path == "/s/1")
        #expect(p.marker(version: "1").path == "/s/1/.complete")
        #expect(p.compiledCache(version: "1").path == "/c/1")
        #expect(p.resumeData.path == "/s/resume.data")
        #expect(p.archive.path == "/s/download.aar")
        #expect(p.installing.path == "/s/.installing")
        let standard = KokoroPaths.standard()
        #expect(standard.support.path.hasSuffix("/Application Support/Aloud/Kokoro"))
        #expect(standard.caches.path.hasSuffix("/Caches/Aloud/Kokoro"))
    }
}
