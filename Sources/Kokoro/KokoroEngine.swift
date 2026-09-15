import Foundation
import KokoroTTS
import Speech
import os

/// What the engine can report. `KokoroError` is not `Sendable` and stays inside the
/// actor; this is the shape of it the rest of the app sees.
public enum KokoroEngineError: Error, Sendable, Equatable {
    case notLoaded
    case load(String)
    case synthesis(String)
    case cancelled
    /// The text phonemized to nothing: a stray symbol, an empty line. Not a failure to
    /// stall a reading on.
    case nothingToSay
}

/// The engine as the provider sees it, so a fake can stand in for it.
public protocol KokoroSynthesizing: Actor {
    func load(root: URL, cache: URL) async throws
    func synthesize(_ text: String, voice: String, speed: Double) async throws -> [Float]
    func unload()
}

/// The SDK behind one actor. `load` builds the `KokoroTTS` and prewarms it, which is
/// where the models compile and specialise the first time; `synthesize` returns 24 kHz
/// mono samples; `unload` gives the memory back.
public actor KokoroEngine: KokoroSynthesizing {
    private var tts: KokoroTTS?
    /// The buckets after the first, warmed once `load` has returned. Internal so the
    /// suite can wait on the sequence it started.
    private(set) var warmTask: Task<Void, Never>?
    /// Bumped by `unload`. A `KokoroTTS.load` already inside the SDK cannot be cancelled,
    /// and without this it would resume and write its model over the nil an unload left,
    /// holding several hundred megabytes that nothing can reach or give back.
    private var loadEpoch = 0
    /// How one bucket is warmed. Nil in the app, where it is the SDK's own `prewarm` on
    /// the model this actor holds; a test hands in its own, because the order, the
    /// cancellation and the handle are worth asserting without CoreML in the room.
    private let prewarmOverride: (@Sendable (String, Float) async -> Void)?
    private let log = Logger(subsystem: "design.kevxu.aloud", category: "kokoro")

    public init() { prewarmOverride = nil }

    /// For the suite: the sequence without the SDK.
    init(prewarm: @escaping @Sendable (String, Float) async -> Void) { prewarmOverride = prewarm }

    public var isLoaded: Bool { tts != nil }

    /// The compute units each stage is asked for, chosen by measurement rather than by
    /// reading. It is the SDK's own `gistDefault`, passed explicitly so the choice is
    /// this app's and the table below says why.
    ///
    /// Swept on 2026-09-15, Apple M2 Pro 16 GB, macOS 26.2, release build, against the
    /// four-bucket bundle, with the compiled-model cache and Core ML's own
    /// specialisation caches warm: each policy was run twice in a row and the second run
    /// read, because switching policy evicts the specialisation and the run after a
    /// switch pays it again. Seconds of wall clock for one `synthesize`; "settled" is
    /// the short sentence once every bucket behind the first has finished prewarming,
    /// which is the number a reader mid-chapter lives with.
    ///
    ///     policy                                  load+warm   2.75s   7.88s  13.14s  settled
    ///     gistDefault (duration .cpuOnly)            1.5-2.4    0.86    0.35    0.70    0.157
    ///     duration .cpuAndGPU, decoderPre ANE        5.4-6.4    1.03    0.43    0.93    0.235
    ///     every stage .cpuAndGPU                     5.5-6.1    1.04    0.44    0.96    0.242
    ///     every stage .all                              20.4    1.34    0.50    0.98    0.251
    ///     generator .cpuAndNeuralEngine, rest .all       280    12.2     5.9    10.0     1.63
    ///
    /// So the SDK's default wins on this bundle, on every sentence and on the wait before
    /// the first one. `perf-investigation.md` in the plan folder concluded the opposite
    /// from the same machine, measuring the duration model at 5 to 8 seconds on the CPU;
    /// that does not reproduce here. The control says why: the one-bucket bundle under
    /// this same policy settles at 0.498 s now, against the 8 to 9 s Task 11 recorded
    /// with it. The old number was Core ML compiling and specialising the graphs, which
    /// costs 40 to 45 seconds once per machine per policy and is cached afterwards, not
    /// the placement of the duration stage. The four buckets are still worth 3.2x on a
    /// short sentence (0.498 s to 0.157 s).
    ///
    /// The two Neural Engine policies are the ones to stay away from, and both were
    /// already documented by the SDK: the generator is GPU-preferred, and asking for it
    /// on the ANE cost 280 s of prewarm and left every sentence 5 to 10 times slower.
    static let computePolicy = KokoroComputePolicy.gistDefault

    /// The most speed the model is worth asking for.
    ///
    /// The duration model rounds each token's frames and clamps them at one, so a
    /// sentence can never be shorter than one frame a token: asked for 3 it delivers
    /// about 2.2, and the ceiling moves with how phoneme-dense the text is. The provider
    /// asks for at most this and hands the rest to a time stretch on the playback, which
    /// makes the reader's speed truthful and, because the prefetch is keyed on what the
    /// engine was asked for, makes every speed at or above it one rendering.
    public static let maxSpeed = 2.0

    /// One sentence per acoustic bucket, in the order a reader meets them.
    ///
    /// The SDK renders a chunk at the fixed shape of the smallest bucket whose seconds
    /// are at least the chunk's predicted duration, and each bucket specialises on its
    /// own first prediction, so a bucket that is never prewarmed pays that
    /// specialisation inside the first sentence that lands in it, mid-reading. The
    /// order is the one that matters most first: a typical opening sentence lands in
    /// the 7-second bucket, short sentences in the 3-second one, long ones in the
    /// 10-second one, and the 15-second one is reached only below 1x, since the
    /// duration model caps a chunk at 128 tokens and 128 tokens is about 8 seconds of
    /// speech at 1x. Each text's bucket was confirmed by synthesizing it and reading
    /// the audio it produced, which is the same number `selectBucket` rounds up.
    static let prewarms: [(text: String, speed: Float)] = [
        (
            "The morning was bright and cold, and the sea beyond the harbour wall lay perfectly still.",
            1
        ),
        ("Nobody really teaches you research.", 1),
        (
            "She had meant to write the letter that evening, but the light went, and the kitchen grew cold, and in the end she read instead.",
            1
        ),
        (
            "She had meant to write the letter that evening, but the light went, and the kitchen grew cold, and in the end she read instead.",
            0.6
        ),
    ]
    static let prewarmVoice = KokoroVoiceID("af_bella")

    /// Loads the SDK and warms the bucket the first sentence is likeliest to land in,
    /// then returns: the reader is not made to wait for buckets that sentence does not
    /// need. The other three warm afterwards, and a `synthesize` that arrives meanwhile
    /// waits for at most the one bucket in flight. Not because of this actor's own
    /// isolation, which `await tts.prewarm` gives up: `KokoroTTS` is itself an actor and
    /// runs a whole prediction without suspending, so the two serialise there. That
    /// property lives in the SDK and could change there.
    public func load(root: URL, cache: URL) async throws {
        guard tts == nil else { return }
        loadEpoch += 1
        let epoch = loadEpoch
        do {
            let loaded = try await KokoroTTS.load(
                resources: .directory(root, compiledModelsDirectory: cache),
                computePolicy: Self.computePolicy)
            let first = Self.prewarms[0]
            try await loaded.prewarm(
                text: first.text, voice: Self.prewarmVoice,
                options: KokoroSynthesisOptions(speed: first.speed))
            // An unload arrived while the SDK was loading. It could not be cancelled, but
            // keeping what it produced would hold the memory the unload asked back.
            guard epoch == loadEpoch else { return }
            tts = loaded
        } catch is CancellationError {
            throw KokoroEngineError.cancelled
        } catch KokoroError.synthesisCancelled {
            throw KokoroEngineError.cancelled
        } catch {
            throw KokoroEngineError.load(error.localizedDescription)
        }
        warmRemainingBuckets()
    }

    /// The buckets the first sentence does not need. A failure here is not a failed
    /// load: the bundle is loaded and every sentence will still be spoken, the first
    /// one into that bucket just pays its own specialisation.
    ///
    /// The handle is not cleared when the sequence ends. Clearing it there raced a
    /// second load: the old sequence's last turn could nil out the handle the new one
    /// had already stored, and a later `unload` would then have nothing to cancel.
    /// A handle to a finished task costs nothing and `cancel()` on one is a no-op.
    func warmRemainingBuckets() {
        warmTask?.cancel()
        warmTask = Task {
            for warm in Self.prewarms.dropFirst() {
                guard !Task.isCancelled else { return }
                await prewarm(warm.text, speed: warm.speed)
            }
        }
    }

    /// One bucket. A failure is logged rather than raised: a bucket that fails to
    /// specialise on every launch is otherwise invisible, and all the reader ever sees
    /// of it is an unexplained pause mid-reading.
    private func prewarm(_ text: String, speed: Float) async {
        if let prewarmOverride {
            await prewarmOverride(text, speed)
            return
        }
        guard let tts else { return }
        do {
            try await tts.prewarm(
                text: text, voice: Self.prewarmVoice, options: KokoroSynthesisOptions(speed: speed))
        } catch is CancellationError {
        } catch KokoroError.synthesisCancelled {
        } catch {
            log.error(
                "Kokoro could not prewarm the bucket at speed \(speed, privacy: .public): \(error.localizedDescription, privacy: .public)"
            )
        }
    }

    public func synthesize(_ text: String, voice: String, speed: Double) async throws -> [Float] {
        guard let tts else { throw KokoroEngineError.notLoaded }
        let audio: KokoroAudio
        do {
            audio = try await tts.synthesize(
                text, voice: KokoroVoiceID(voice), options: KokoroSynthesisOptions(speed: Float(speed)))
        } catch is CancellationError {
            throw KokoroEngineError.cancelled
        } catch KokoroError.synthesisCancelled {
            throw KokoroEngineError.cancelled
        } catch KokoroError.emptyText, KokoroError.emptyPhonemizerOutput {
            throw KokoroEngineError.nothingToSay
        } catch KokoroError.inaudibleChunk {
            throw KokoroEngineError.nothingToSay
        } catch KokoroPhonemizerError.emptyOutput {
            // The SDK maps its own text-processing errors onto `KokoroError` but lets
            // the phonemizer's own emptiness through untouched, so a line of "***" -
            // a Markdown rule - arrives here rather than as `emptyPhonemizerOutput`.
            // It is the same nothing, and a reading must not stall on it.
            throw KokoroEngineError.nothingToSay
        } catch {
            throw KokoroEngineError.synthesis(error.localizedDescription)
        }
        guard audio.sampleRate == Int(KokoroPlayback.sampleRate) else {
            throw KokoroEngineError.synthesis("unexpected sample rate \(audio.sampleRate)")
        }
        return audio.samples
    }

    /// Gives the model back. A prewarm already inside a CoreML prediction holds its own
    /// reference until that prediction returns, and the SDK checks cancellation only at
    /// stage boundaries, so the memory comes back within about a second on a warm cache
    /// and within tens of seconds on a cold one, rather than at once.
    public func unload() {
        loadEpoch += 1
        warmTask?.cancel()
        warmTask = nil
        tts = nil
    }
}
