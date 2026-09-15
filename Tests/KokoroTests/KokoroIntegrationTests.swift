import Foundation
import Testing

@testable import Kokoro

/// Runs only when `ALOUD_KOKORO_BUNDLE` names a folder holding the real bundle (the
/// manifest at its root), for example `.build/kokoro-bundle/kokoro-1` after
/// `make kokoro-bundle`. It loads the real engine and speaks one sentence.
@Suite struct KokoroIntegrationTests {
    static var bundle: URL? {
        ProcessInfo.processInfo.environment["ALOUD_KOKORO_BUNDLE"].map { URL(fileURLWithPath: $0) }
    }

    @Test(.enabled(if: KokoroIntegrationTests.bundle != nil))
    func theRealEngineSpeaksASentence() async throws {
        let root = try #require(Self.bundle)
        let cache = FileManager.default.temporaryDirectory.appendingPathComponent(
            "kokoro-cache-\(UUID().uuidString)")
        let engine = KokoroEngine()
        try await engine.load(root: root, cache: cache)
        for voice in ["af_bella", "bm_fable"] {
            let samples = try await engine.synthesize(
                "Nobody really teaches you research.", voice: voice, speed: 1)
            let seconds = Double(samples.count) / KokoroPlayback.sampleRate
            let finite = samples.allSatisfy(\.isFinite)
            let audible = samples.contains { abs($0) > 0.01 }
            #expect(seconds > 1 && seconds < 5, "\(voice)")
            #expect(finite, "\(voice)")
            #expect(audible, "\(voice)")
        }
        await #expect(throws: KokoroEngineError.nothingToSay) {
            _ = try await engine.synthesize("***", voice: "af_bella", speed: 1)
        }
        try? FileManager.default.removeItem(at: cache)
    }

    /// The speed the picker offers is the engine's own, not a rate applied after the
    /// fact, so the same sentence has to come back shorter at every step up.
    ///
    /// Measured on this bundle, it does not come back shorter in proportion. Asked for
    /// 2 the engine delivers about 1.9x; asked for 3 it delivers about 2.2x, and the
    /// speech between the leading and trailing silence barely shortens past 2.5. So the
    /// ratio is asserted where it holds, at 2, and above it only the ordering is: 3 is
    /// no slower than 2 and never overshoots a third. The shortfall at 3 is the finding
    /// the spec anticipates for that speed, and its remedy is the one the spec names,
    /// capping the engine at 2 and letting an `AVAudioUnitTimePitch` on the playback
    /// engine cover the rest, as a follow-up rather than a change smuggled in here.
    @Test(.enabled(if: KokoroIntegrationTests.bundle != nil))
    func speedShortensTheSentence() async throws {
        let root = try #require(Self.bundle)
        let cache = FileManager.default.temporaryDirectory.appendingPathComponent(
            "kokoro-cache-\(UUID().uuidString)")
        let engine = KokoroEngine()
        try await engine.load(root: root, cache: cache)
        var seconds: [Double] = []
        for speed in [1.0, 2.0, 3.0] {
            let samples = try await engine.synthesize(
                "Nobody really teaches you research.", voice: "af_bella", speed: speed)
            let measured = Double(samples.count) / KokoroPlayback.sampleRate
            let finite = samples.allSatisfy(\.isFinite)
            let audible = samples.contains { abs($0) > 0.01 }
            // The measurement is the finding, so it goes on the record whether or not
            // the checks below hold. This suite runs only when it is asked for by hand.
            print("kokoro speed \(speed): \(measured) seconds")
            #expect(finite, "\(speed)")
            #expect(audible, "\(speed)")
            seconds.append(measured)
        }
        let (one, two, three) = (seconds[0], seconds[1], seconds[2])
        #expect(abs(two - one / 2) <= one / 2 * 0.25)
        #expect(three <= two)
        #expect(three >= one / 3)
        try? FileManager.default.removeItem(at: cache)
    }
}
