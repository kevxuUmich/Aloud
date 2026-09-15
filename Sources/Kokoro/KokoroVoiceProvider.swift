import Foundation
import Speech
import os

/// The second engine behind the protocol the player speaks through. The voices are the
/// catalogue when the model is installed and nothing otherwise; a sentence is rendered
/// by the engine chunk by chunk and each chunk is played as it lands; the next sentence
/// is rendered ahead.
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
    /// True while a sentence this provider was asked to speak is waiting on the models
    /// to load. It is what tells the app model, when a load fails, whether the audio the
    /// reader can hear right now is this engine's dropped sentence or another engine's
    /// sentence that is still being spoken: a Kokoro voice picked mid-sentence starts the
    /// warm without stopping the sentence already in the air, because a pick takes at the
    /// next sentence.
    public private(set) var isWaitingOnLoad = false
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
    /// The sentence in the air, and the one rendered ahead of it.
    private var current: SentenceRender?
    private var prepared: SentenceRender?
    /// The last render made, whatever became of it. The engine is one actor and the SDK
    /// runs a whole chunk without suspending, so every render is chained after the one
    /// before it; this is the one the next is chained after.
    private var lastRender: SentenceRender?
    /// A `prepare` that arrived while the models were still loading, which is every
    /// first sentence of a reading, kept until the sentence waiting on that load has its
    /// render, so that it is chained after it and not before it.
    private var pendingPrepare: (text: String, voice: Voice, rate: Rate)?
    /// The voice the buckets are warmed in: whatever was last picked, previewed or
    /// spoken, and the catalogue's first before any of those.
    private var warmVoice = KokoroCatalogue.voices[0].kokoroID
    /// The speed the engine rendered the sentence in the air at, or nil when nothing is.
    /// A speed change is heard by stretching the rest of that sentence by the reader's
    /// speed over this one.
    private var renderedSpeed: Double?
    /// The reader's speed, kept so a change made while a sentence is still rendering is
    /// what that sentence is played at when it lands.
    private var rate: Rate?
    /// The level the reader last chose. `speak` is handed one with the sentence, but a
    /// change made while that sentence is still being rendered would otherwise be heard
    /// only from the sentence after it.
    private var level = 1.0

    /// The silence between two chunks of one sentence: the length of a spoken comma,
    /// which is what the SDK splits at. The model's own 0.75 s of silence at a seam is
    /// trimmed off by the engine, and this is what stands in its place.
    static let seamPause: Duration = .milliseconds(180)
    static let seam = [Float](repeating: 0, count: Int(seamPause.seconds * KokoroPlayback.sampleRate))

    /// Keyed on what the engine was asked for, not on the `Rate`: every speed at or
    /// above `KokoroEngine.maxSpeed` is one rendering. A change between two rates that
    /// share an engine speed leaves the sentence rendered ahead alone.
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
        renderedSpeed = nil
        current?.cancel()
        current = nil
        let gen = generation
        guard let kokoro = voice.flatMap({ KokoroCatalogue.voice(for: $0.id) }) else {
            finish(after: pause, generation: gen, onFinish)
            return
        }
        let key = CacheKey(text: text, voice: kokoro.kokoroID, speed: Self.split(rate).engine)
        // With the models here, the render is taken or made before this returns, so the
        // prepare the player hands over on the same turn is chained after it.
        if isLoaded { start(key) }
        speakTask = Task {
            if !isLoaded {
                warm(voice)
                // Set before the await and cleared after it, both without suspending in
                // between, so a failure reported from inside that warm sees it.
                isWaitingOnLoad = true
                await warmTask?.value
                isWaitingOnLoad = false
                guard gen == generation else { return }
                // The warm failed. The sentence still has to be reported finished or the
                // reading stalls here; the app model's own check falls back to the system
                // voice and speaks it again.
                guard isLoaded else {
                    finish(after: pause, generation: gen, onFinish)
                    return
                }
                start(key)
                // The prepare the player handed over for the next sentence while this
                // load was in flight: it was kept rather than dropped, and now that this
                // sentence's render is made, it goes behind it.
                startPendingPrepare()
            }
            guard gen == generation, let render = current else { return }
            await play(render, pause: pause, generation: gen, onFinish)
        }
    }

    /// The render for the sentence about to be spoken: the one made ahead when it is
    /// this sentence, else a new one. Either way it is the sentence in the air from here.
    private func start(_ key: CacheKey) {
        if let prepared, prepared.key == key {
            self.prepared = nil
            current = prepared
        } else {
            prepared?.cancel()
            prepared = nil
            current = make(key)
        }
        renderedSpeed = key.speed
    }

    /// A render chained after the last one made.
    private func make(_ key: CacheKey) -> SentenceRender {
        let render = SentenceRender(key: key, engine: engine, after: lastRender)
        lastRender = render
        return render
    }

    /// Plays one sentence's render: each chunk is queued the moment it is rendered, with
    /// the seam after every one but the last, and the sentence is finished, after its
    /// pause, once every queued buffer has been heard. A chunk that failed or had nothing
    /// to say is skipped, so the rest of the sentence is still heard; a sentence with no
    /// chunk to hear finishes silently, so the reading never stalls.
    private func play(
        _ render: SentenceRender, pause: Duration, generation gen: Int,
        _ onFinish: @escaping @MainActor () -> Void
    ) async {
        playback.setVolume(level)
        playback.setRate(stretch)
        let chunks = await render.chunks ?? []
        guard gen == generation else { return }
        log.debug("Kokoro speaks \(chunks.count) chunks rendered at \(render.key.speed, privacy: .public)")
        let tally = Tally()
        for i in chunks.indices {
            let samples = await render.samples(ofChunk: i)
            guard gen == generation else { return }
            guard let samples, !samples.isEmpty else { continue }
            tally.queued += 1
            if tally.queued == 1 { log.debug("Kokoro queued the first chunk") }
            playback.enqueue(i + 1 < chunks.count ? samples + Self.seam : samples) { [weak self] in
                guard let self, gen == self.generation else { return }
                tally.heard += 1
                self.finishIfHeard(tally, after: pause, generation: gen, onFinish)
            }
        }
        tally.allQueued = true
        finishIfHeard(tally, after: pause, generation: gen, onFinish)
    }

    /// How much of a sentence has been queued and heard. A class so the completions and
    /// the loop that queues them share one count.
    @MainActor private final class Tally {
        var queued = 0
        var heard = 0
        var allQueued = false
    }

    private func finishIfHeard(
        _ tally: Tally, after pause: Duration, generation gen: Int,
        _ onFinish: @escaping @MainActor () -> Void
    ) {
        guard tally.allQueued, tally.heard == tally.queued else { return }
        finish(after: pause, generation: gen, onFinish)
    }

    /// The reader's speed over the speed the sentence in the air was rendered at. 1 while
    /// nothing is in the air.
    private var stretch: Double {
        guard let renderedSpeed, let rate else { return 1 }
        return rate.factor / renderedSpeed
    }

    public func prepare(_ text: String, voice: Voice?, rate: Rate) {
        guard let voice, let kokoro = KokoroCatalogue.voice(for: voice.id) else { return }
        let key = CacheKey(text: text, voice: kokoro.kokoroID, speed: Self.split(rate).engine)
        if prepared?.key == key { return }
        // Not loaded yet, or a sentence is waiting on that load: the render for that
        // sentence is not made until the load lands, and this must go behind it.
        guard isLoaded, !isWaitingOnLoad else {
            pendingPrepare = (text, voice, rate)
            return
        }
        prepared?.cancel()
        prepared = make(key)
    }

    /// The prefetch that was waiting for the models.
    private func startPendingPrepare() {
        guard isLoaded, let pending = pendingPrepare else { return }
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

    /// The speed of the sentence in the air, changed where it stands: the rest of it is
    /// stretched on the playback by the new speed over the one it was rendered at, so
    /// nothing is stopped, rendered again or rewound. The next sentence is rendered at
    /// the new speed; the one already rendered ahead is rendered again at it now, unless
    /// the two speeds ask the engine for the same thing, which every speed past the cap
    /// does. False only while nothing is in the air, when there is nothing to stretch.
    public func setRate(_ new: Rate) -> Bool {
        guard let renderedSpeed else { return false }
        rate = new
        let stretch = new.factor / renderedSpeed
        log.debug("Kokoro stretches the sentence in the air by \(stretch, privacy: .public)")
        playback.setRate(stretch)
        if let prepared, prepared.key.speed != Self.split(new).engine {
            prepared.cancel()
            self.prepared = make(
                CacheKey(text: prepared.key.text, voice: prepared.key.voice, speed: Self.split(new).engine))
        }
        return true
    }

    public func stop() {
        cancelCurrent()
        generation += 1
        rate = nil
        renderedSpeed = nil
        current?.cancel()
        current = nil
        prepared?.cancel()
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
        previewTask = Task {
            if !isLoaded {
                warm(voice)
                await warmTask?.value
            }
            guard gen == generation, isLoaded else { return }
            let render = make(CacheKey(text: VoicePreview.text, voice: kokoro.kokoroID, speed: 1))
            playback.setVolume(1)
            playback.setRate(1)
            guard let chunks = await render.chunks, gen == generation else { return }
            for i in chunks.indices {
                let samples = await render.samples(ofChunk: i)
                guard gen == generation else { return }
                guard let samples, !samples.isEmpty else { continue }
                playback.enqueue(samples) {}
            }
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
            // A prepare kept while this load was in flight. When a sentence is waiting on
            // this same load, that sentence's own task issues it, after its render is
            // made; issued here it would be chained in front of that render.
            if !isWaitingOnLoad { startPendingPrepare() }
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
