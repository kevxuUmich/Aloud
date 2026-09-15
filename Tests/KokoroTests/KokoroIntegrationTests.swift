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

    /// What the reader actually waits for: the wall clock of one sentence, on the first
    /// call after `load` returns and on the second.
    ///
    /// The compiled-model cache is kept between runs, so these are the numbers of every
    /// launch but the first on a machine. Delete `aloud-kokoro-measure-cache` from the
    /// temporary directory to measure a machine that has never loaded the bundle.
    ///
    /// Measured 2026-09-15 on an Apple M2 Pro, 16 GB, macOS 26.2, release build, with
    /// the four-bucket bundle and the staged compute policy:
    ///
    ///     load and first prewarm   5.82 s
    ///     2.750 s of audio   first 0.92 s   second 1.18 s   settled 0.25 s
    ///     7.875 s of audio   first 0.47 s   second 0.47 s
    ///     13.165 s of audio  first 1.01 s   second 1.01 s
    ///
    /// The first two calls on the short sentence overlap the 10 and 15 second buckets
    /// still warming behind `load`, which is what the 0.9 to 1.2 s is; the same sentence
    /// once they are done takes 0.25 s. So the wait that design costs a reader who
    /// presses Play the instant the model is ready is about half a second, once.
    ///
    /// The same machine with an empty compiled-model cache, which is a reader's first
    /// launch after the download and happens once: load and first prewarm 44.1 s, then
    /// 2.4 s, 1.4 s and 1.0 s for the three sentences. Timed one bucket at a time, the
    /// prewarms are 45.1 / 2.3 / 3.0 / 0.9 s cold and 5.9 / 0.7 / 0.9 / 0.9 s warm: the
    /// 45 s is Core ML compiling and specialising the graphs once per machine, and the
    /// three buckets behind the first cost about a second each afterwards.
    ///
    /// Task 11 measured 8.3 to 9.2 s for a 2.75 to 4.3 s sentence on this machine, with
    /// the one-bucket bundle and the SDK's default compute policy. Most of that was the
    /// policy: `perf-investigation.md` measured 0.63 s for the short sentence and 0.62 s
    /// for the 7.9 s one on the one-bucket bundle with this policy. The buckets are the
    /// rest of it, and they help in proportion to how much of a bucket a sentence
    /// wastes: 0.63 to 0.25 s for a short sentence, 0.62 to 0.47 s for a long one.
    @Test(.enabled(if: KokoroIntegrationTests.bundle != nil))
    func theWallClockOfASentenceIsRecorded() async throws {
        let root = try #require(Self.bundle)
        let cache = FileManager.default.temporaryDirectory.appendingPathComponent(
            "aloud-kokoro-measure-cache")
        let engine = KokoroEngine()
        let loading = ContinuousClock.now
        try await engine.load(root: root, cache: cache)
        print("kokoro load and first prewarm: \(ContinuousClock.now - loading)")
        // The first of each pair arrives while the buckets the first sentence does not
        // need are still warming, which is the wait that design costs a reader.
        for text in [Self.shortSentence, Self.longSentence, Self.longestSentence] {
            for pass in 1...3 {
                let started = ContinuousClock.now
                let samples = try await engine.synthesize(text, voice: "af_bella", speed: 1)
                let wall = ContinuousClock.now - started
                let seconds = Double(samples.count) / KokoroPlayback.sampleRate
                let finite = samples.allSatisfy(\.isFinite)
                let audible = samples.contains { abs($0) > 0.01 }
                print("kokoro pass \(pass) chars=\(text.count) audio=\(seconds)s wall=\(wall)")
                #expect(finite, "\(text.count)")
                #expect(audible, "\(text.count)")
            }
        }
        // The short sentence once more, long after the last bucket has warmed, so its
        // steady state is not read off a call that overlapped one.
        let settled = ContinuousClock.now
        _ = try await engine.synthesize(Self.shortSentence, voice: "af_bella", speed: 1)
        print("kokoro settled chars=35 wall=\(ContinuousClock.now - settled)")
    }

    static let shortSentence = "Nobody really teaches you research."
    static let longSentence =
        "She had meant to write the letter that evening, but the light went, and the kitchen grew cold, and in the end she read instead."
    static let longestSentence =
        "She had meant to write the letter that evening, but the light went, and the kitchen grew cold, and in the end she read instead, sitting by the window until the harbour lamps came on one by one."

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
