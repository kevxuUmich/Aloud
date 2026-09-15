import Foundation
import Speech
import os

/// The second engine behind the protocol the player speaks through. The voices are the
/// catalogue when the model is installed and nothing otherwise; a sentence is rendered
/// by the engine and played by the player; the next one is rendered ahead.
/// Observable because the picker draws `isWarming` as a spinner on the row it belongs
/// to: without it the spinner appears on the pick that renders it and then stays until
/// something else redraws the list.
@Observable @MainActor
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
    /// Bumped by `warm` and `unload`. A load that an unload overtook must not report
    /// itself loaded, nor clear the bookkeeping of the warm that came after it.
    private var warmGeneration = 0
    private(set) var speakTask: Task<Void, Never>?
    private(set) var pauseTask: Task<Void, Never>?
    private(set) var warmTask: Task<Void, Never>?
    private(set) var previewTask: Task<Void, Never>?
    /// The one sentence rendered ahead.
    private var prepared: (key: CacheKey, task: Task<[Float]?, Never>)?
    /// A `prepare` that could not be started when it arrived, kept until it can be.
    /// Two moments drop it otherwise: the models are still loading, which is every
    /// first sentence of a reading, and the sentence the reader is waiting on is still
    /// being rendered. The engine is one actor, so a prefetch started then would put
    /// that sentence behind it, and the SDK honours cancellation only between chunks.
    private var pendingPrepare: (text: String, voice: Voice, rate: Rate)?
    /// The voice the buckets are warmed in: whatever was last picked, previewed or
    /// spoken, and the catalogue's first before any of those.
    private var warmVoice = KokoroCatalogue.voices[0].kokoroID
    /// The speed the sentence being spoken was rendered and is being played at, or nil
    /// when nothing is. `setRate` compares against it to decide whether the samples in
    /// hand can be played at a new speed, and `speak` plays at it so a change made while
    /// a sentence was still rendering is heard on that sentence rather than the next.
    private var rate: Rate?
    /// The level the reader last chose. `speak` is handed one with the sentence, but a
    /// change made while that sentence is still being rendered would otherwise be heard
    /// only from the sentence after it, which on this engine is seconds away.
    private var level = 1.0
    /// How many renders the reader is waiting on are in flight. A prefetch starts only
    /// at zero. Counted rather than flagged because `speak` bumps it before its task
    /// runs, so the `prepare` the player hands over on the same turn already sees it.
    private var rendering = 0

    /// Keyed on what the engine was asked for, not on the `Rate`: every speed at or
    /// above `KokoroEngine.maxSpeed` is one rendering. That is what lets `setRate`
    /// answer a change from 2.25x to 3x with the playback's time stretch and no
    /// synthesis at all, and it is why the sentence rendered ahead survives the change
    /// rather than being cancelled with the one being heard.
    struct CacheKey: Equatable {
        let text: String
        let voice: String
        let speed: Double
    }

    /// What the model is asked for, and what is left for the playback to stretch.
    /// Below the cap the engine does all of it and the stretch is 1.
    static func split(_ rate: Rate) -> (engine: Double, stretch: Double) {
        let engine = min(rate.factor, KokoroEngine.maxSpeed)
        return (engine, rate.factor / engine)
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
    /// The picker opening asks again, so a load that failed once does not hide the
    /// voices for the rest of the session.
    public nonisolated func refreshVoices() { loadFailed.set(false) }

    public func speak(
        _ text: String, voice: Voice?, rate: Rate, pause: Duration, volume: Double,
        onWord: @escaping @MainActor (NSRange) -> Void, onFinish: @escaping @MainActor () -> Void
    ) {
        cancelCurrent()
        generation += 1
        level = volume
        self.rate = rate
        let gen = generation
        guard let kokoro = voice.flatMap({ KokoroCatalogue.voice(for: $0.id) }) else {
            finish(after: pause, generation: gen, onFinish)
            return
        }
        rendering += 1
        speakTask = Task {
            defer { finishedRendering() }
            if !isLoaded {
                warm(voice)
                await warmTask?.value
            }
            guard gen == generation else { return }
            // The warm failed. The sentence still has to be reported finished or the
            // reading stalls here; the app model's own check falls back to the system
            // voice and speaks it again.
            guard isLoaded else {
                finish(after: pause, generation: gen, onFinish)
                return
            }
            let samples = await samples(for: text, voice: kokoro, rate: rate)
            guard gen == generation else { return }
            guard let samples, !samples.isEmpty else {
                finish(after: pause, generation: gen, onFinish)
                return
            }
            playback.play(samples, volume: level, rate: Self.split(self.rate ?? rate).stretch) {
                [weak self] in
                guard let self, gen == self.generation else { return }
                self.finish(after: pause, generation: gen, onFinish)
            }
        }
    }

    public func prepare(_ text: String, voice: Voice?, rate: Rate) {
        guard let voice, let kokoro = KokoroCatalogue.voice(for: voice.id) else { return }
        let key = CacheKey(text: text, voice: kokoro.kokoroID, speed: Self.split(rate).engine)
        if prepared?.key == key { return }
        guard isLoaded, rendering == 0 else {
            pendingPrepare = (text, voice, rate)
            return
        }
        prepared?.task.cancel()
        let engine = engine
        prepared = (
            key, Task { try? await engine.synthesize(text, voice: key.voice, speed: key.speed) }
        )
    }

    /// A render the reader was waiting on has returned, been cancelled, or given up.
    /// The prefetch that was held off for it goes now.
    private func finishedRendering() {
        rendering -= 1
        startPendingPrepare()
    }

    /// The prefetch that was waiting for the models or for the reader's own sentence.
    private func startPendingPrepare() {
        guard isLoaded, rendering == 0, let pending = pendingPrepare else { return }
        pendingPrepare = nil
        prepare(pending.text, voice: pending.voice, rate: pending.rate)
    }

    /// The level of the sentence being played, changed where it stands: this engine owns
    /// its player node, so a re-speak would be a whole re-synthesis for nothing.
    public func setVolume(_ volume: Double) -> Bool {
        level = volume
        playback.setVolume(volume)
        return true
    }

    /// The speed of the sentence being played, changed where it stands when the samples
    /// in hand can be played at it: above `KokoroEngine.maxSpeed` the engine was asked
    /// for the cap and the rest is the playback's time stretch, so every speed from 2x
    /// up shares one rendering and a change among them needs no new audio. Anything else
    /// is false, and the player speaks the sentence again, which is the only way to hear
    /// a speed the engine has not rendered.
    public func setRate(_ new: Rate) -> Bool {
        guard let rate, Self.split(rate).engine == Self.split(new).engine else { return false }
        self.rate = new
        playback.setRate(Self.split(new).stretch)
        return true
    }

    public func stop() {
        cancelCurrent()
        generation += 1
        rate = nil
        prepared?.task.cancel()
        prepared = nil
        pendingPrepare = nil
        playback.stop()
    }

    /// The preview sentence at 1x in the chosen voice, through the same player, once
    /// the model is loaded.
    public func preview(_ voice: Voice) {
        stop()
        generation += 1
        let gen = generation
        guard let kokoro = KokoroCatalogue.voice(for: voice.id) else { return }
        rendering += 1
        previewTask = Task {
            defer { finishedRendering() }
            if !isLoaded {
                warm(voice)
                await warmTask?.value
            }
            guard gen == generation, isLoaded else { return }
            guard let samples = await samples(for: VoicePreview.text, voice: kokoro, rate: .x1),
                gen == generation
            else {
                return
            }
            playback.play(samples, volume: 1, rate: 1) {}
        }
    }

    /// Loads the models off the main actor, once, warming them in the voice given.
    /// Called when a Kokoro voice is picked and at launch when the saved voice is one;
    /// `voice` is that voice, so the buckets are warmed in the one the reader will hear
    /// rather than in a default they may never pick.
    public func warm(_ voice: Voice? = nil) {
        if let kokoro = voice.flatMap({ KokoroCatalogue.voice(for: $0.id) }) {
            warmVoice = kokoro.kokoroID
        }
        guard !isLoaded, warmTask == nil, let root = store.installedRoot else { return }
        // A fresh attempt: whatever the last one concluded is no longer the answer, so
        // the voices are back until this one says otherwise.
        loadFailed.set(false)
        isWarming = true
        warmGeneration += 1
        let epoch = warmGeneration
        let cache = store.compiledCache
        let engine = engine
        let voiceID = warmVoice
        warmTask = Task {
            var failure: String?
            var cancelled = false
            do {
                try await engine.load(root: root, cache: cache, voice: voiceID)
            } catch KokoroEngineError.cancelled {
                cancelled = true
            } catch {
                failure = (error as? KokoroEngineError).map(Self.text) ?? error.localizedDescription
            }
            // An unload, or a newer warm, overtook this load: its answer is stale, and
            // the bookkeeping below is the later attempt's to write.
            guard epoch == warmGeneration else { return }
            if let failure {
                loadFailed.set(true)
                log.error("Kokoro failed to load: \(failure, privacy: .public)")
                onLoadFailure?(failure)
            } else if !cancelled {
                isLoaded = true
                loadFailed.set(false)
            }
            isWarming = false
            warmTask = nil
            // The prepare the player handed over for sentence 2 while this load was in
            // flight: it was kept rather than dropped, and this is where it is issued.
            startPendingPrepare()
        }
    }

    /// Gives the memory back, and the audio device with it. Picking an Apple voice calls
    /// it.
    public func unload() {
        stop()
        playback.shutdown()
        // Past the epoch before the cancel: a load already through the SDK cannot be
        // cancelled, and this is what stops it reporting itself loaded afterwards.
        warmGeneration += 1
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
        let speed = Self.split(rate).engine
        let key = CacheKey(text: text, voice: voice.kokoroID, speed: speed)
        if let prepared, prepared.key == key {
            self.prepared = nil
            return await prepared.task.value
        }
        // A miss: the sentence rendered ahead is not the one being read, and the reader
        // has moved past it, so it is not worth keeping or finishing.
        prepared?.task.cancel()
        prepared = nil
        do {
            return try await engine.synthesize(text, voice: voice.kokoroID, speed: speed)
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
