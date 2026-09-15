import Foundation
import Speech
import Testing

@testable import Kokoro

/// An engine that answers from a table and can be told to fail or to take its time.
actor FakeEngine: KokoroSynthesizing {
    struct Call: Equatable { let text: String; let voice: String; let speed: Double }
    var calls: [Call] = []
    var loads: [URL] = []
    var unloads = 0
    var failLoad: String?
    var failSynthesis: KokoroEngineError?
    var gate: CheckedContinuation<Void, Never>?
    var holdNext = false
    var loadGate: CheckedContinuation<Void, Never>?
    var holdLoadNext = false

    func load(root: URL, cache: URL) async throws {
        loads.append(root)
        if holdLoadNext {
            holdLoadNext = false
            await withCheckedContinuation { loadGate = $0 }
        }
        if let failLoad { throw KokoroEngineError.load(failLoad) }
    }
    func synthesize(_ text: String, voice: String, speed: Double) async throws -> [Float] {
        calls.append(Call(text: text, voice: voice, speed: speed))
        if holdNext {
            holdNext = false
            await withCheckedContinuation { gate = $0 }
            try Task.checkCancellation()
        }
        if let failSynthesis { throw failSynthesis }
        return [Float](repeating: 0.1, count: text.count)
    }
    func unload() { unloads += 1 }
    func release() {
        gate?.resume()
        gate = nil
    }
    func hold() { holdNext = true }
    /// The same for the load, so a test can unload while the models are still arriving.
    func holdLoad() { holdLoadNext = true }
    func releaseLoad() {
        loadGate?.resume()
        loadGate = nil
    }
    func setFailLoad(_ s: String?) { failLoad = s }
    func setFailSynthesis(_ e: KokoroEngineError?) { failSynthesis = e }
}

/// Plays nothing and lets the test say when the buffer has been heard.
@MainActor final class FakePlayback: KokoroPlaying {
    struct Played { let samples: [Float]; let volume: Double; let rate: Double }
    var played: [Played] = []
    var stops = 0
    private var completion: (@MainActor () -> Void)?
    func play(
        _ samples: [Float], volume: Double, rate: Double, completion: @escaping @MainActor () -> Void
    ) {
        played.append(Played(samples: samples, volume: volume, rate: rate))
        self.completion = completion
    }
    var volumes: [Double] = []
    var shutdowns = 0
    func setVolume(_ volume: Double) { volumes.append(volume) }
    func shutdown() { shutdowns += 1 }
    /// Counts the stop and keeps the completion: a real player can call back after one,
    /// and it must be the provider's own generation guard that swallows it.
    func stop() { stops += 1 }
    func finish() {
        let c = completion
        completion = nil
        c?()
    }
}

@MainActor final class HeldSleep {
    var asked: [Duration] = []
    private var waiting: [CheckedContinuation<Void, Never>] = []
    func sleep(_ d: Duration) async throws {
        asked.append(d)
        await withCheckedContinuation { waiting.append($0) }
        try Task.checkCancellation()
    }
    func release() {
        let w = waiting
        waiting = []
        w.forEach { $0.resume() }
    }
}

@Suite @MainActor struct KokoroVoiceProviderTests {
    let bella = KokoroCatalogue.voices[0].voice
    let fable = KokoroCatalogue.voices[6].voice

    func make(installed: Bool = true) throws -> (
        KokoroVoiceProvider, FakeEngine, FakePlayback, HeldSleep, KokoroStore
    ) {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        let paths = KokoroPaths(
            support: root.appendingPathComponent("s"), caches: root.appendingPathComponent("c"))
        if installed {
            try FileManager.default.createDirectory(
                at: paths.modelDirectory(version: KokoroRelease.current.version),
                withIntermediateDirectories: true)
            try Data().write(to: paths.marker(version: KokoroRelease.current.version))
        }
        let store = KokoroStore(paths: paths, release: KokoroRelease.current, downloader: FakeDownloader())
        let engine = FakeEngine()
        let playback = FakePlayback()
        let held = HeldSleep()
        let provider = KokoroVoiceProvider(store: store, engine: engine, playback: playback) {
            try await held.sleep($0)
        }
        return (provider, engine, playback, held, store)
    }

    /// Polls until `condition` holds, for work that lands on a later turn.
    func until(_ condition: () -> Bool) async -> Bool {
        let deadline = ContinuousClock.now + .seconds(5)
        while !condition() {
            guard ContinuousClock.now < deadline else { return false }
            try? await Task.sleep(for: .milliseconds(5))
        }
        return true
    }

    /// The same, for a condition read off an actor.
    func eventually(_ condition: () async -> Bool) async -> Bool {
        let deadline = ContinuousClock.now + .seconds(5)
        while await !condition() {
            guard ContinuousClock.now < deadline else { return false }
            try? await Task.sleep(for: .milliseconds(5))
        }
        return true
    }

    /// The voices are there when the model is, and not before: an empty list is what
    /// makes the picker show download rows and a saved voice fall back.
    @Test func voicesFollowTheStore() async throws {
        let (absent, _, _, _, store) = try make(installed: false)
        await store.start()
        #expect(absent.voices.isEmpty)
        #expect(absent.defaultVoice == nil)
        let (installed, _, _, _, store2) = try make()
        await store2.start()
        #expect(installed.voices.map(\.id) == KokoroCatalogue.voices.map(\.id))
    }

    /// A sentence is synthesized at the rate's factor, played at the volume, and reported
    /// finished once its pause has passed. The word callback is never used.
    @Test func speakSynthesizesPlaysPausesAndFinishes() async throws {
        let (p, engine, playback, held, store) = try make()
        await store.start()
        p.warm()
        await p.warmTask?.value
        var finished = 0
        var words = 0
        p.speak(
            "Nobody really teaches you research.", voice: bella, rate: .x15, pause: .milliseconds(200),
            volume: 0.5,
            onWord: { _ in words += 1 }, onFinish: { finished += 1 })
        #expect(await until { playback.played.count == 1 })
        #expect(
            await engine.calls == [
                .init(text: "Nobody really teaches you research.", voice: "af_bella", speed: 1.5)
            ])
        #expect(playback.played.first?.volume == 0.5)
        #expect(finished == 0)
        playback.finish()
        #expect(await until { held.asked == [.milliseconds(200)] })
        #expect(finished == 0)
        held.release()
        await p.pauseTask?.value
        #expect(finished == 1)
        #expect(words == 0)
    }

    /// A speak before the engine is loaded loads it first, once, then speaks.
    @Test func speakWarmsWhenCold() async throws {
        let (p, engine, playback, _, store) = try make()
        await store.start()
        p.speak("One.", voice: fable, rate: .x1, pause: .zero, volume: 1, onWord: { _ in }, onFinish: {})
        #expect(await until { playback.played.count == 1 })
        #expect(await engine.loads.count == 1)
        #expect(await engine.calls.last?.voice == "bm_fable")
        #expect(p.isLoaded)
    }

    /// Stop cancels the synthesis in flight, stops playback, and a completion from the
    /// cancelled sentence never reaches the caller.
    @Test func stopCancelsAndGuardsLateCompletions() async throws {
        let (p, engine, playback, held, store) = try make()
        await store.start()
        p.warm()
        await p.warmTask?.value
        await engine.hold()
        var finished = 0
        p.speak(
            "One.", voice: bella, rate: .x1, pause: .milliseconds(100), volume: 1, onWord: { _ in },
            onFinish: { finished += 1 })
        #expect(await eventually { await engine.calls.count == 1 })
        p.stop()
        await engine.release()
        await p.speakTask?.value
        #expect(playback.played.isEmpty)
        #expect(playback.stops == 1)
        // A sentence that was already playing: its completion arrives after the stop.
        p.speak(
            "Two.", voice: bella, rate: .x1, pause: .zero, volume: 1, onWord: { _ in },
            onFinish: { finished += 1 })
        #expect(await until { playback.played.count == 1 })
        p.stop()
        playback.finish()
        #expect(finished == 0)
        _ = held
    }

    /// `prepare` renders the next sentence ahead; a `speak` for the same text, voice and
    /// rate plays it without asking the engine again. Anything else is a miss.
    @Test func prepareIsAOneSlotCache() async throws {
        let (p, engine, playback, _, store) = try make()
        await store.start()
        p.warm()
        await p.warmTask?.value
        p.prepare("Two.", voice: bella, rate: .x1)
        #expect(await eventually { await engine.calls.count == 1 })
        p.speak("Two.", voice: bella, rate: .x1, pause: .zero, volume: 1, onWord: { _ in }, onFinish: {})
        #expect(await until { playback.played.count == 1 })
        #expect(await engine.calls.count == 1)
        // A different rate is a different sentence to the engine.
        p.prepare("Three.", voice: bella, rate: .x1)
        p.speak("Three.", voice: bella, rate: .x2, pause: .zero, volume: 1, onWord: { _ in }, onFinish: {})
        #expect(await until { playback.played.count == 2 })
        #expect(await engine.calls.count == 3)
        #expect(await engine.calls.last == .init(text: "Three.", voice: "af_bella", speed: 2))
    }

    /// The player hands over sentence 2 the instant it asks for sentence 1, and on the
    /// first sentence of a reading the models are still loading. The request is
    /// remembered rather than dropped, so the very first boundary is a cache hit.
    @Test func aPrepareBeforeTheModelsAreLoadedIsNotLost() async throws {
        let (p, engine, playback, _, store) = try make()
        await store.start()
        await engine.holdLoad()
        p.speak("One.", voice: bella, rate: .x1, pause: .zero, volume: 1, onWord: { _ in }, onFinish: {})
        p.prepare("Two.", voice: bella, rate: .x1)
        #expect(await eventually { await engine.loads.count == 1 })
        #expect(await engine.calls.isEmpty)
        await engine.releaseLoad()
        #expect(await eventually { await engine.calls.count == 2 })
        #expect(await engine.calls.map(\.text) == ["One.", "Two."])
        #expect(playback.played.count == 1)
    }

    /// The engine is one actor, so a prefetch started while the reader's own sentence is
    /// being rendered puts that sentence behind it. The prefetch waits for the sentence
    /// in the air and then runs, once.
    @Test func aPrefetchWaitsForTheSentenceBeingSpoken() async throws {
        let (p, engine, playback, _, store) = try make()
        await store.start()
        p.warm()
        await p.warmTask?.value
        await engine.hold()
        p.speak("One.", voice: bella, rate: .x1, pause: .zero, volume: 1, onWord: { _ in }, onFinish: {})
        #expect(await eventually { await engine.calls.count == 1 })
        p.prepare("Two.", voice: bella, rate: .x1)
        try await Task.sleep(for: .milliseconds(50))
        #expect(await engine.calls.count == 1)
        await engine.release()
        #expect(await until { playback.played.count == 1 })
        #expect(await eventually { await engine.calls.count == 2 })
        #expect(await engine.calls.map(\.text) == ["One.", "Two."])
    }

    /// A sentence that phonemizes to nothing finishes silently and on time, so a stray
    /// symbol never stalls a reading.
    @Test func nothingToSayFinishesSilently() async throws {
        let (p, engine, playback, held, store) = try make()
        await store.start()
        p.warm()
        await p.warmTask?.value
        await engine.setFailSynthesis(.nothingToSay)
        var finished = 0
        p.speak(
            "***", voice: bella, rate: .x1, pause: .milliseconds(50), volume: 1, onWord: { _ in },
            onFinish: { finished += 1 })
        #expect(await until { held.asked.count == 1 })
        held.release()
        await p.pauseTask?.value
        #expect(finished == 1)
        #expect(playback.played.isEmpty)
    }

    /// A level change reaches the node that is playing and asks the engine for nothing:
    /// dragging the slider must not re-render the sentence.
    @Test func setVolumeReachesThePlaybackWithoutTheEngine() async throws {
        let (p, engine, playback, _, store) = try make()
        await store.start()
        p.warm()
        await p.warmTask?.value
        p.speak("One.", voice: bella, rate: .x1, pause: .zero, volume: 1, onWord: { _ in }, onFinish: {})
        #expect(await until { playback.played.count == 1 })
        #expect(p.setVolume(0.25))
        #expect(playback.volumes == [0.25])
        #expect(await engine.calls.count == 1)
        #expect(playback.played.count == 1)
        // A change made while the next sentence is still rendering is heard on that
        // sentence too, not only on the one after it.
        await engine.hold()
        p.speak("Two.", voice: bella, rate: .x1, pause: .zero, volume: 1, onWord: { _ in }, onFinish: {})
        #expect(await eventually { await engine.calls.count == 2 })
        #expect(p.setVolume(0.5))
        await engine.release()
        #expect(await until { playback.played.count == 2 })
        #expect(playback.played.last?.volume == 0.5)
    }

    /// A preview interrupts whatever is playing and speaks the preview sentence at 1x in
    /// the chosen voice.
    @Test func previewInterruptsAndSpeaksTheSentence() async throws {
        let (p, engine, playback, _, store) = try make()
        await store.start()
        p.warm()
        await p.warmTask?.value
        p.speak("One.", voice: bella, rate: .x2, pause: .zero, volume: 1, onWord: { _ in }, onFinish: {})
        #expect(await until { playback.played.count == 1 })
        p.preview(fable)
        await p.previewTask?.value
        #expect(playback.stops == 1)
        #expect(await engine.calls.last == .init(text: VoicePreview.text, voice: "bm_fable", speed: 1))
        #expect(playback.played.count == 2)
    }

    /// Warm loads once and reports while it does; unload gives the memory back and a
    /// second warm loads again. A picked Apple voice is what calls unload.
    @Test func warmAndUnload() async throws {
        let (p, engine, playback, _, store) = try make()
        await store.start()
        #expect(!p.isWarming && !p.isLoaded)
        p.warm()
        #expect(p.isWarming)
        p.warm()
        await p.warmTask?.value
        #expect(!p.isWarming && p.isLoaded)
        #expect(await engine.loads.count == 1)
        #expect(await engine.loads.first == store.installedRoot)
        p.unload()
        #expect(!p.isLoaded)
        // The audio device goes back with the model's memory: nothing will be spoken
        // until a Kokoro voice is picked again, and `play` restarts the engine itself.
        #expect(playback.shutdowns == 1)
        #expect(await eventually { await engine.unloads == 1 })
        p.warm()
        await p.warmTask?.value
        #expect(await engine.loads.count == 2)
    }

    /// A load failure empties the list and says why, so the player's own check falls
    /// back to the system voice with a notice.
    @Test func aLoadFailureEmptiesTheListAndReports() async throws {
        let (p, engine, _, _, store) = try make()
        await store.start()
        await engine.setFailLoad("no metal")
        var reported: [String] = []
        p.onLoadFailure = { reported.append($0) }
        p.warm()
        await p.warmTask?.value
        #expect(reported == ["no metal"])
        #expect(p.voices.isEmpty)
        #expect(!p.isLoaded && !p.isWarming)
        // A later install clears the failure.
        await engine.setFailLoad(nil)
        p.warm()
        await p.warmTask?.value
        #expect(p.voices.count == 7)
    }

    /// An unload while the models are still arriving wins: the load that lands after it
    /// does not report itself loaded, and it does not clear the warm that comes next.
    @Test func unloadDuringWarmLeavesTheProviderUnloaded() async throws {
        let (p, engine, _, _, store) = try make()
        await store.start()
        await engine.holdLoad()
        p.warm()
        #expect(await eventually { await engine.loads.count == 1 })
        let stale = p.warmTask
        p.unload()
        await engine.releaseLoad()
        await stale?.value
        #expect(!p.isLoaded)
        #expect(!p.isWarming)
        #expect(p.warmTask == nil)
        // The next warm is a load of its own, not a no-op behind the stale one.
        p.warm()
        await p.warmTask?.value
        #expect(await engine.loads.count == 2)
        #expect(p.isLoaded)
    }

    /// A load that fails still finishes the sentence, so a reading never stalls on it;
    /// the app model's own check is what falls back to the system voice.
    @Test func aFailedWarmStillFinishesTheSentence() async throws {
        let (p, engine, playback, held, store) = try make()
        await store.start()
        await engine.setFailLoad("no metal")
        var finished = 0
        p.speak(
            "One.", voice: bella, rate: .x1, pause: .milliseconds(50), volume: 1, onWord: { _ in },
            onFinish: { finished += 1 })
        #expect(await until { held.asked.count == 1 })
        held.release()
        await p.pauseTask?.value
        #expect(finished == 1)
        #expect(playback.played.isEmpty)
        #expect(!p.isLoaded)
    }

    /// The picker opening asks again, so a load that failed once does not hide the
    /// voices for the rest of the session.
    @Test func refreshVoicesClearsALoadFailure() async throws {
        let (p, engine, _, _, store) = try make()
        await store.start()
        await engine.setFailLoad("no metal")
        p.warm()
        await p.warmTask?.value
        #expect(p.voices.isEmpty)
        p.refreshVoices()
        #expect(p.voices.count == 7)
    }

    /// Above `KokoroEngine.maxSpeed` the engine is asked for the cap and the playback
    /// stretches what is left, so 3x is really 3x rather than the 2.2x the model gives.
    @Test func aRateAboveTheCapIsSplitBetweenTheEngineAndThePlayback() async throws {
        let (p, engine, playback, _, store) = try make()
        await store.start()
        p.warm()
        await p.warmTask?.value
        p.speak("One.", voice: bella, rate: .x3, pause: .zero, volume: 1, onWord: { _ in }, onFinish: {})
        #expect(await until { playback.played.count == 1 })
        #expect(await engine.calls.last?.speed == 2)
        #expect(playback.played.last?.rate == 1.5)
        p.speak("Two.", voice: bella, rate: .x15, pause: .zero, volume: 1, onWord: { _ in }, onFinish: {})
        #expect(await until { playback.played.count == 2 })
        #expect(await engine.calls.last?.speed == 1.5)
        #expect(playback.played.last?.rate == 1)
    }

    /// The prize of capping in the provider: every rate at or above the cap is one
    /// rendering, so a sentence prepared at 2.5x is a hit when it is spoken at 3x and the
    /// reader's speed change costs no synthesis at all.
    @Test func ratesAboveTheCapShareOneRendering() async throws {
        let (p, engine, playback, _, store) = try make()
        await store.start()
        p.warm()
        await p.warmTask?.value
        p.prepare("Two.", voice: bella, rate: .x25)
        #expect(await eventually { await engine.calls.count == 1 })
        p.speak("Two.", voice: bella, rate: .x3, pause: .zero, volume: 1, onWord: { _ in }, onFinish: {})
        #expect(await until { playback.played.count == 1 })
        #expect(await engine.calls.count == 1)
        #expect(playback.played.last?.rate == 1.5)
    }

    /// The cap holds for every speed the picker offers, so no rate can ask the model for
    /// something it answers by saturating.
    @Test func theEngineIsNeverAskedForMoreThanTheCap() async throws {
        let (p, engine, playback, _, store) = try make()
        await store.start()
        p.warm()
        await p.warmTask?.value
        for (n, rate) in Rate.allCases.enumerated() {
            p.speak(
                "\(n).", voice: bella, rate: rate, pause: .zero, volume: 1, onWord: { _ in },
                onFinish: {})
            #expect(await until { playback.played.count == n + 1 })
        }
        let speeds = await engine.calls.map(\.speed)
        #expect(speeds.allSatisfy { $0 <= KokoroEngine.maxSpeed }, "\(speeds)")
        #expect(speeds == Rate.allCases.map { min($0.factor, KokoroEngine.maxSpeed) }, "\(speeds)")
    }

    @Test func warmWithNothingInstalledDoesNothing() async throws {
        let (p, engine, _, _, store) = try make(installed: false)
        await store.start()
        p.warm()
        await p.warmTask?.value
        #expect(await engine.loads.isEmpty)
        #expect(!p.isLoaded)
    }
}
