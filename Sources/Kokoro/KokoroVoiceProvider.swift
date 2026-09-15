import Foundation
import Speech
import os

/// The second engine behind the protocol the player speaks through. The voices are the
/// catalogue when the model is installed and nothing otherwise; a sentence is rendered
/// by the engine and played by the player; the next one is rendered ahead.
@MainActor
public final class KokoroVoiceProvider: VoiceProvider {
    public let store: KokoroStore
    private let engine: any KokoroSynthesizing
    private let playback: any KokoroPlaying
    private let sleep: @Sendable (Duration) async throws -> Void
    private let log = Logger(subsystem: "design.kevxu.aloud", category: "kokoro")

    /// True while the models load; the picker draws it as a spinner on the picked row.
    public private(set) var isWarming = false
    public private(set) var isLoaded = false
    /// Called with one sentence when the models fail to load. The list is empty until
    /// the next warm, so the player falls back through its own check.
    public var onLoadFailure: (@MainActor (String) -> Void)?
    /// A load that failed hides the voices until something changes; a lock-guarded
    /// flag because `voices` is read nonisolated.
    private let loadFailed = LoadFlag()

    /// Bumped by `stop`, `speak` and `preview`, so a completion from an earlier sentence
    /// is ignored.
    private var generation = 0
    private(set) var speakTask: Task<Void, Never>?
    private(set) var pauseTask: Task<Void, Never>?
    private(set) var warmTask: Task<Void, Never>?
    private(set) var previewTask: Task<Void, Never>?
    /// The one sentence rendered ahead.
    private var prepared: (key: CacheKey, task: Task<[Float]?, Never>)?

    struct CacheKey: Equatable {
        let text: String
        let voice: String
        let rate: Rate
    }

    public init(
        store: KokoroStore, engine: any KokoroSynthesizing = KokoroEngine(),
        playback: any KokoroPlaying = KokoroPlayback(),
        sleep: @escaping @Sendable (Duration) async throws -> Void = { try await Task.sleep(for: $0) }
    ) {
        self.store = store
        self.engine = engine
        self.playback = playback
        self.sleep = sleep
    }

    public nonisolated var voices: [Voice] {
        store.isInstalledNow && !loadFailed.get() ? KokoroCatalogue.speechVoices : []
    }
    /// The default is always the system's; a Kokoro voice is a choice.
    public nonisolated var defaultVoice: Voice? { nil }
    public nonisolated func refreshVoices() {}

    public func speak(
        _ text: String, voice: Voice?, rate: Rate, pause: Duration, volume: Double,
        onWord: @escaping @MainActor (NSRange) -> Void, onFinish: @escaping @MainActor () -> Void
    ) {
        cancelCurrent()
        generation += 1
        let gen = generation
        guard let kokoro = voice.flatMap({ KokoroCatalogue.voice(for: $0.id) }) else {
            onFinish()
            return
        }
        speakTask = Task {
            if !isLoaded {
                warm()
                await warmTask?.value
            }
            guard gen == generation, isLoaded else { return }
            let samples = await samples(for: text, voice: kokoro, rate: rate)
            guard gen == generation else { return }
            guard let samples, !samples.isEmpty else {
                finish(after: pause, generation: gen, onFinish)
                return
            }
            playback.play(samples, volume: volume) { [weak self] in
                guard let self, gen == self.generation else { return }
                self.finish(after: pause, generation: gen, onFinish)
            }
        }
    }

    public func prepare(_ text: String, voice: Voice?, rate: Rate) {
        guard isLoaded, let kokoro = voice.flatMap({ KokoroCatalogue.voice(for: $0.id) }) else { return }
        let key = CacheKey(text: text, voice: kokoro.kokoroID, rate: rate)
        if prepared?.key == key { return }
        prepared?.task.cancel()
        let engine = engine
        prepared = (
            key, Task { try? await engine.synthesize(text, voice: kokoro.kokoroID, speed: rate.factor) }
        )
    }

    public func stop() {
        cancelCurrent()
        generation += 1
        prepared?.task.cancel()
        prepared = nil
        playback.stop()
    }

    /// The preview sentence at 1x in the chosen voice, through the same player, once
    /// the model is loaded.
    public func preview(_ voice: Voice) {
        stop()
        generation += 1
        let gen = generation
        guard let kokoro = KokoroCatalogue.voice(for: voice.id) else { return }
        previewTask = Task {
            if !isLoaded {
                warm()
                await warmTask?.value
            }
            guard gen == generation, isLoaded else { return }
            guard let samples = await samples(for: VoicePreview.text, voice: kokoro, rate: .x1),
                gen == generation
            else {
                return
            }
            playback.play(samples, volume: 1) {}
        }
    }

    /// Loads the models off the main actor, once. Called when a Kokoro voice is picked
    /// and at launch when the saved voice is one.
    public func warm() {
        guard !isLoaded, warmTask == nil, let root = store.installedRoot else { return }
        isWarming = true
        let cache = store.compiledCache
        let engine = engine
        warmTask = Task {
            do {
                try await engine.load(root: root, cache: cache)
                isLoaded = true
                loadFailed.set(false)
            } catch KokoroEngineError.cancelled {
            } catch {
                loadFailed.set(true)
                let message = (error as? KokoroEngineError).map(Self.text) ?? error.localizedDescription
                log.error("Kokoro failed to load: \(message, privacy: .public)")
                onLoadFailure?(message)
            }
            isWarming = false
            warmTask = nil
        }
    }

    /// Gives the memory back. Picking an Apple voice calls it.
    public func unload() {
        stop()
        warmTask?.cancel()
        warmTask = nil
        isWarming = false
        isLoaded = false
        let engine = engine
        Task { await engine.unload() }
    }

    /// The prepared samples when they are the ones asked for, else a fresh render. A
    /// failure is logged and comes back nil, which the caller finishes silently.
    private func samples(for text: String, voice: KokoroVoice, rate: Rate) async -> [Float]? {
        let key = CacheKey(text: text, voice: voice.kokoroID, rate: rate)
        if let prepared, prepared.key == key {
            self.prepared = nil
            return await prepared.task.value
        }
        do {
            return try await engine.synthesize(text, voice: voice.kokoroID, speed: rate.factor)
        } catch KokoroEngineError.cancelled {
            return nil
        } catch {
            log.error(
                "Kokoro could not speak a sentence: \((error as? KokoroEngineError).map(Self.text) ?? error.localizedDescription, privacy: .public)"
            )
            return nil
        }
    }

    private func finish(
        after pause: Duration, generation gen: Int, _ onFinish: @escaping @MainActor () -> Void
    ) {
        guard pause > .zero else {
            onFinish()
            return
        }
        pauseTask = Task { [sleep] in
            try? await sleep(pause)
            guard !Task.isCancelled, gen == generation else { return }
            pauseTask = nil
            onFinish()
        }
    }

    private func cancelCurrent() {
        speakTask?.cancel()
        speakTask = nil
        previewTask?.cancel()
        previewTask = nil
        pauseTask?.cancel()
        pauseTask = nil
    }

    static func text(_ error: KokoroEngineError) -> String {
        switch error {
        case .notLoaded: "the model is not loaded"
        case .load(let s), .synthesis(let s): s
        case .cancelled: "cancelled"
        case .nothingToSay: "nothing to say"
        }
    }
}

private final class LoadFlag: @unchecked Sendable {
    private let lock = NSLock()
    private var failed = false
    func get() -> Bool { lock.withLock { failed } }
    func set(_ value: Bool) { lock.withLock { failed = value } }
}
