import Foundation
import KokoroTTS
import Speech

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
    /// The buckets after the first, warmed once `load` has returned.
    private var warmTask: Task<Void, Never>?

    public init() {}

    public var isLoaded: Bool { tts != nil }

    /// The SDK's own benchmark policy, not its `gistDefault`. `gistDefault` pins the
    /// duration model to the CPU to dodge an iOS MPSGraph stall, and on this bundle's
    /// padded 128-token duration graph that costs 5 to 8 seconds a sentence; see
    /// `perf-investigation.md` in the plan folder. Part B of the fix wave settles the
    /// final policy from a wider sweep.
    static let computePolicy = KokoroComputePolicy(
        duration: .cpuAndGPU, f0ntrain: .cpuAndGPU, decoderPre: .cpuAndNeuralEngine,
        generator: .cpuAndGPU)

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
    /// need. The other three warm afterwards on this actor, so a `synthesize` that
    /// arrives meanwhile waits for at most the one bucket in flight.
    public func load(root: URL, cache: URL) async throws {
        guard tts == nil else { return }
        do {
            let loaded = try await KokoroTTS.load(
                resources: .directory(root, compiledModelsDirectory: cache),
                computePolicy: Self.computePolicy)
            let first = Self.prewarms[0]
            try await loaded.prewarm(
                text: first.text, voice: Self.prewarmVoice,
                options: KokoroSynthesisOptions(speed: first.speed))
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
    private func warmRemainingBuckets() {
        warmTask?.cancel()
        warmTask = Task {
            for warm in Self.prewarms.dropFirst() {
                guard !Task.isCancelled, let tts else { return }
                try? await tts.prewarm(
                    text: warm.text, voice: Self.prewarmVoice,
                    options: KokoroSynthesisOptions(speed: warm.speed))
            }
            warmTask = nil
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

    public func unload() {
        warmTask?.cancel()
        warmTask = nil
        tts = nil
    }
}
