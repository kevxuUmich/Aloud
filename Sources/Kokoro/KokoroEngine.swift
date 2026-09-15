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
    /// `voice` is the voice the prewarm should use: the one the reader picked, because a
    /// voice this process has not spoken in costs about a third of a second on its first
    /// sentence, and the prewarm is where that belongs.
    func load(root: URL, cache: URL, voice: String) async throws
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
    /// The voice every bucket is warmed in: the one the reader had picked when the models
    /// were loaded. A voice this process has never spoken in costs about 0.35 s extra on
    /// its first sentence, measured, and warming in the picked voice pays that inside the
    /// wait the reader already accepted rather than on the sentence they pressed Play for.
    ///
    /// It is the voice of the load, not of every pick. A `load` that finds the models
    /// already here returns without warming anything, so a second Kokoro voice picked in
    /// the same session pays that 0.35 s on its own first sentence. Re-warming four
    /// buckets on every pick would cost more than it saves, so this is deliberate.
    private var prewarmVoice = KokoroVoiceID(KokoroEngine.defaultPrewarmVoice)
    private let log = Logger(subsystem: "design.kevxu.aloud", category: "kokoro")

    public init() { prewarmOverride = nil }

    /// For the suite: the sequence without the SDK.
    init(prewarm: @escaping @Sendable (String, Float) async -> Void) { prewarmOverride = prewarm }

    public var isLoaded: Bool { tts != nil }

    /// The compute units each stage is asked for, chosen by measurement rather than by
    /// reading. It is the policy the SDK's own benchmark harness uses, not its
    /// `gistDefault`, and it is passed explicitly so the choice is this app's.
    ///
    /// Swept on 2026-09-15, Apple M2 Pro 16 GB, macOS 26.2, release build, against the
    /// four-bucket bundle. Two things had to be held still to get a comparable reading.
    /// The compiled-model cache must be warm, and Core ML's own specialisation cache is
    /// evicted by switching policy, so each policy was given a throwaway run first and
    /// then three fresh processes. Seconds of wall clock, one sentence per acoustic
    /// bucket, "first" being the first `synthesize` after `load` returns and "third"
    /// the third call for the same sentence:
    ///
    ///     policy         load   7s first   3s first   7s third   3s third
    ///     staged         5.42   0.79       0.98       0.35       0.23
    ///                    5.43   0.82       1.06       0.35       0.23
    ///                    5.44   0.79       1.01       0.35       0.23
    ///     gistDefault    1.63   1.72       1.41       0.28       0.46
    ///                    1.66   3.28       1.40       0.31       0.21
    ///                    3.34   4.09       1.35       0.33       0.20
    ///
    /// `gistDefault` is the cheaper load and, by about 0.05 s, the cheaper settled
    /// sentence. It loses the one that matters: the first sentence after a load costs it
    /// 1.4 to 4.1 seconds against this policy's 0.8 to 1.1, and it is erratic where this
    /// one repeats to within 30 ms. The spec's number is about the first sentence, so
    /// this is the policy.
    ///
    /// The difference is where each pays for its duration graph. `gistDefault` pins the
    /// duration model to the CPU, and that graph is about 32,000 primitive ops, built
    /// per process on first use; this policy puts it on the GPU, where MPSGraph
    /// specialises it once per machine, caches it on disk, and hands every later process
    /// a graph that is ready. So `gistDefault` moves the cost off `load` and onto the
    /// reader's first sentence, which is exactly the wrong way round.
    ///
    /// That also settles `perf-investigation.md`, which measured the duration stage at
    /// 5.0 to 8.1 s on `.cpuOnly` and read it as steady state. The cost is real and it is
    /// the per-process CPU graph build, but through `KokoroTTS` it amortises: the third
    /// call is 0.20 to 0.46 s. The investigation drove `executeKokoroSynthesis` with
    /// models it instantiated itself rather than through the facade the app uses, which
    /// is the likeliest reason its calls never reached a settled state.
    ///
    /// Two policies to stay away from, both of which the SDK already documents. Asking
    /// for the generator on the Neural Engine cost 280 s of prewarm and left every
    /// sentence 5 to 10 times slower; `.all` for every stage lets Core ML find the same
    /// trap by itself, at 20 s of prewarm and one call in 48 s.
    static let computePolicy = KokoroComputePolicy(
        duration: .cpuAndGPU, f0ntrain: .cpuAndGPU, decoderPre: .cpuAndNeuralEngine,
        generator: .cpuAndGPU)

    /// The most speed the model is worth asking for.
    ///
    /// The duration model rounds each token's frames and clamps them at one, so a
    /// sentence can never be shorter than one frame a token: asked for 3 it delivers
    /// about 2.2, and the ceiling moves with how phoneme-dense the text is. The provider
    /// asks for at most this and hands the rest to a time stretch on the playback, which
    /// makes the reader's speed truthful and, because the prefetch is keyed on what the
    /// engine was asked for, makes every speed at or above it one rendering. That is what
    /// `KokoroVoiceProvider.setRate` spends: a change among those speeds is answered by
    /// moving the time stretch, so the sentence being heard is not re-synthesized and the
    /// one rendered ahead of it is not thrown away.
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
    /// The voice a warm falls back to when the caller names none.
    static let defaultPrewarmVoice = "af_bella"

    /// Loads the SDK and warms the bucket the first sentence is likeliest to land in,
    /// then returns: the reader is not made to wait for buckets that sentence does not
    /// need. The other three warm afterwards, and a `synthesize` that arrives meanwhile
    /// waits for at most the one bucket in flight. Not because of this actor's own
    /// isolation, which `await tts.prewarm` gives up: `KokoroTTS` is itself an actor and
    /// runs a whole prediction without suspending, so the two serialise there. That
    /// property lives in the SDK and could change there.
    public func load(root: URL, cache: URL, voice: String) async throws {
        if tts != nil {
            // A model is already here, but the provider sends `load` and `unload` from
            // the main actor and this call can reach the actor with an `unload` already
            // waiting behind it. Yielding lets anything enqueued run, and then this asks
            // the same question the slow path asks at its own suspension point: is the
            // model this is about to report still the current one? What it is guarding
            // against is the provider setting `isLoaded` over a model that is about to
            // go, after which every sentence would finish silently with nothing spoken
            // and no warm to recover, because `warm()` will not run again while
            // `isLoaded` is true.
            //
            // This narrows that window; it does not close it. `Task.yield()` gives up
            // the actor once, which is not a promise that an `unload` the provider has
            // not yet enqueued will run during it, and one that arrives after this
            // returns leaves the same inconsistency. Closing it means the provider
            // sending its load and its unload down one ordered chain rather than as two
            // unstructured tasks, which is a change to `KokoroVoiceProvider` rather than
            // to this actor, and a known follow-up rather than something this guard has
            // already done.
            let epoch = loadEpoch
            await Task.yield()
            guard tts != nil, epoch == loadEpoch else { throw KokoroEngineError.cancelled }
            return
        }
        loadEpoch += 1
        let epoch = loadEpoch
        prewarmVoice = KokoroVoiceID(voice)
        do {
            let loaded = try await KokoroTTS.load(
                resources: .directory(root, compiledModelsDirectory: cache),
                computePolicy: Self.computePolicy)
            let first = Self.prewarms[0]
            try await loaded.prewarm(
                text: first.text, voice: prewarmVoice,
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
                text: text, voice: prewarmVoice, options: KokoroSynthesisOptions(speed: speed))
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
