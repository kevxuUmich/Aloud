import Foundation
import Testing

@testable import Kokoro

/// Runs only when `ALOUD_KOKORO_BUNDLE` names a folder holding the real bundle (the
/// manifest at its root), for example `.build/kokoro-bundle/kokoro-2` after
/// `make kokoro-bundle`. It loads the real engine and speaks one sentence.
/// Serialized: three engines loading and predicting at once fight over the same GPU and
/// the same Core ML compiler, and the wall clocks below are the point of the suite. Run
/// in parallel the short sentence read thirty seconds rather than a fifth of one.
@Suite(.serialized) struct KokoroIntegrationTests {
    static var bundle: URL? {
        ProcessInfo.processInfo.environment["ALOUD_KOKORO_BUNDLE"].map { URL(fileURLWithPath: $0) }
    }

    @Test(.enabled(if: KokoroIntegrationTests.bundle != nil))
    func theRealEngineSpeaksASentence() async throws {
        let root = try #require(Self.bundle)
        let cache = FileManager.default.temporaryDirectory.appendingPathComponent(
            "kokoro-cache-\(UUID().uuidString)")
        let engine = KokoroEngine()
        try await engine.load(root: root, cache: cache, voice: "af_bella")
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
    /// call after `load` returns and on the calls after it, at 1x and at the speed the
    /// provider asks for when the reader is at anything above 2x.
    ///
    /// The compiled-model cache is kept between runs, so these are the numbers of every
    /// launch but the first on a machine. Delete `aloud-kokoro-measure-cache` from the
    /// temporary directory to measure a machine that has never loaded the bundle.
    ///
    /// Measured 2026-09-15 on an Apple M2 Pro, 16 GB, macOS 26.2, release build, this
    /// test run on its own, with the four-bucket bundle and `KokoroEngine.computePolicy`:
    ///
    ///     load and first prewarm   1.66 s
    ///
    ///     audio    speed   first   second   third
    ///     2.750 s    1x    1.64     1.03     0.99      (settled, later: 0.159)
    ///     1.475 s    2x    0.164    0.158    0.158
    ///     7.875 s    1x    0.371    0.533    0.367
    ///     4.450 s    2x    0.309    0.273    0.274
    ///     13.14 s    1x    0.738    0.721    0.707
    ///     7.315 s    2x    0.600    0.633    0.699
    ///
    /// The short sentence's first three calls overlap the 7, 10 and 15 second buckets
    /// still warming behind `load`; the same sentence once they are done takes 0.159 s,
    /// which is the "settled" line the test prints last. So the wait that design costs a
    /// reader who presses Play the instant the model reports ready is about a second,
    /// once, and nothing after it.
    ///
    /// The same machine the first time it ever loads this bundle under this policy: load
    /// and first prewarm 44.0 s, then 3.7 / 1.8 / 1.0 s for the short sentence. That is
    /// Core ML compiling and specialising the graphs, and macOS caches it per machine and
    /// per compute policy. Running the whole gated suite re-pays it, because the other
    /// two cases each build a throwaway compiled-model cache, which is why this suite is
    /// serialized and why these numbers were taken with the test run on its own.
    ///
    /// Task 11 measured 8.3 to 9.2 s for a 2.75 to 4.3 s sentence on this machine, with
    /// the one-bucket bundle and the same compute policy the app passes today. Neither
    /// half of that reproduces now: the one-bucket bundle settles at 0.498 s here. The
    /// old number was the Core ML specialisation above, paid on every process because the
    /// measurement never reached a settled state. The four buckets are worth a real 3.2x
    /// on top: 0.498 s to 0.159 s for a short sentence.
    @Test(.enabled(if: KokoroIntegrationTests.bundle != nil))
    func theWallClockOfASentenceIsRecorded() async throws {
        let root = try #require(Self.bundle)
        let cache = FileManager.default.temporaryDirectory.appendingPathComponent(
            "aloud-kokoro-measure-cache")
        let engine = KokoroEngine()
        let loading = ContinuousClock.now
        try await engine.load(root: root, cache: cache, voice: "af_bella")
        print("kokoro load and first prewarm: \(ContinuousClock.now - loading)")
        // The first of each pair arrives while the buckets the first sentence does not
        // need are still warming, which is the wait that design costs a reader.
        // Both speeds the provider ever asks for: 1, and the cap it hands anything above
        // 2x, which is what a reader at 3x is really costing the engine.
        for text in [Self.shortSentence, Self.longSentence, Self.longestSentence] {
            for speed in [1.0, KokoroEngine.maxSpeed] {
                for pass in 1...3 {
                    let started = ContinuousClock.now
                    let samples = try await engine.synthesize(text, voice: "af_bella", speed: speed)
                    let wall = ContinuousClock.now - started
                    let seconds = Double(samples.count) / KokoroPlayback.sampleRate
                    let finite = samples.allSatisfy(\.isFinite)
                    let audible = samples.contains { abs($0) > 0.01 }
                    print(
                        "kokoro pass \(pass) speed=\(speed) chars=\(text.count) audio=\(seconds)s wall=\(wall)"
                    )
                    #expect(finite, "\(text.count)")
                    #expect(audible, "\(text.count)")
                    // A real-time factor under one, which is the least a render-ahead of
                    // one sentence needs to keep up. An absolute bound would be brittle;
                    // this one has a several-fold margin on the numbers above and still
                    // catches a return to the one-bucket, iPhone-policy behaviour, which
                    // was three. Only the last pass: the first two overlap the buckets
                    // still warming behind `load`.
                    if pass == 3 { #expect(wall < .seconds(seconds), "\(text.count) at \(speed)") }
                }
            }
        }
        // The short sentence once more, long after the last bucket has warmed, so its
        // steady state is not read off a call that overlapped one.
        let settled = ContinuousClock.now
        let last = try await engine.synthesize(Self.shortSentence, voice: "af_bella", speed: 1)
        let settledWall = ContinuousClock.now - settled
        print("kokoro settled chars=35 wall=\(settledWall)")
        #expect(settledWall < .seconds(Double(last.count) / KokoroPlayback.sampleRate))
    }

    static let shortSentence = "Nobody really teaches you research."
    static let longSentence =
        "She had meant to write the letter that evening, but the light went, and the kitchen grew cold, and in the end she read instead."
    static let longestSentence =
        "She had meant to write the letter that evening, but the light went, and the kitchen grew cold, and in the end she read instead, sitting by the window until the harbour lamps came on one by one."

    /// What the engine itself does with speed, which is why the provider caps it.
    ///
    /// Asked for 2 the engine delivers about 1.9x; asked for 3 it delivers about 2.2x,
    /// and the speech barely shortens past 2.5, because the duration model cannot give a
    /// token fewer than one frame. So the ratio is asserted where it holds, at 2, and
    /// above it only that 3 is no slower than 2. Nothing here asserts that 3 gets close
    /// to a third: it does not, and that is the finding. `KokoroEngine.maxSpeed` is the
    /// remedy the spec names, and `KokoroVoiceProvider` never asks this engine for more
    /// than 2; the rest is an `AVAudioUnitTimePitch` in `KokoroPlayback`.
    @Test(.enabled(if: KokoroIntegrationTests.bundle != nil))
    func speedShortensTheSentence() async throws {
        let root = try #require(Self.bundle)
        let cache = FileManager.default.temporaryDirectory.appendingPathComponent(
            "kokoro-cache-\(UUID().uuidString)")
        let engine = KokoroEngine()
        try await engine.load(root: root, cache: cache, voice: "af_bella")
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
        try? FileManager.default.removeItem(at: cache)
    }
}
