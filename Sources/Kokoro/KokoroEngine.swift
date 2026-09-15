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
/// where the four models compile the first time; `synthesize` returns 24 kHz mono
/// samples; `unload` gives the memory back.
public actor KokoroEngine: KokoroSynthesizing {
    private var tts: KokoroTTS?

    public init() {}

    public var isLoaded: Bool { tts != nil }

    public func load(root: URL, cache: URL) async throws {
        guard tts == nil else { return }
        do {
            let loaded = try await KokoroTTS.load(resources: .directory(root, compiledModelsDirectory: cache))
            try await loaded.prewarm(text: VoicePreview.text, voice: KokoroVoiceID("af_bella"))
            tts = loaded
        } catch is CancellationError {
            throw KokoroEngineError.cancelled
        } catch KokoroError.synthesisCancelled {
            throw KokoroEngineError.cancelled
        } catch {
            throw KokoroEngineError.load(error.localizedDescription)
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

    public func unload() { tts = nil }
}
