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

    func load(root: URL, cache: URL) async throws {
        loads.append(root)
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
    func setFailLoad(_ s: String?) { failLoad = s }
    func setFailSynthesis(_ e: KokoroEngineError?) { failSynthesis = e }
}

/// Plays nothing and lets the test say when the buffer has been heard.
@MainActor final class FakePlayback: KokoroPlaying {
    struct Played { let samples: [Float]; let volume: Double }
    var played: [Played] = []
    var stops = 0
    private var completion: (@MainActor () -> Void)?
    func play(_ samples: [Float], volume: Double, completion: @escaping @MainActor () -> Void) {
        played.append(Played(samples: samples, volume: volume))
        self.completion = completion
    }
    func stop() {
        stops += 1
        completion = nil
    }
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
                at: paths.modelDirectory(version: "1"), withIntermediateDirectories: true)
            try Data().write(to: paths.marker(version: "1"))
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
        let (p, engine, _, _, store) = try make()
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

    @Test func warmWithNothingInstalledDoesNothing() async throws {
        let (p, engine, _, _, store) = try make(installed: false)
        await store.start()
        p.warm()
        await p.warmTask?.value
        #expect(await engine.loads.isEmpty)
        #expect(!p.isLoaded)
    }
}
