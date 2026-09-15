# Kokoro chunk streaming implementation plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** A Kokoro sentence is heard from its first chunk, with no dead stops between its chunks, and a speed change mid-sentence is heard where the reader is rather than from the start of the sentence after a re-render.

**Architecture:** `KokoroEngine` gains `chunks(of:)`, the SDK's own split of a sentence, and trims the silence the model puts around every render.
A new `SentenceRender` renders one sentence's chunks in order, chained after the render before it.
`KokoroPlayback` queues buffers instead of replacing them, and `KokoroVoiceProvider` queues each chunk as it lands, inserts a fixed beat between chunks, stretches the rest of a sentence when the speed changes, and re-renders the sentence prepared ahead at the new speed.

**Tech Stack:** Swift 6.2 strict concurrency, Swift Testing, AVFoundation, the `KokoroTTS` product of the kokoro-coreml fork at revision `2932a26444b8deba2a6be6c0aa45c0424efaefe1` (unchanged).

**Spec:** `docs/superpowers/specs/2026-09-15-kokoro-chunk-streaming-design.md`

## Global Constraints

- macOS 26 only; Swift 6 language mode with strict concurrency in every target. `Speech` stays free of the SDK; `VoiceProvider` and `Player` are not changed by this plan.
- `onWord` is never called for a Kokoro voice.
- Constants: `Silence.threshold = 0.002`, `Silence.margin = 720` samples (30 ms at 24 kHz), `KokoroVoiceProvider.seamPause = .milliseconds(180)`. They live in `Sources/Kokoro`, which the literal lint does not cover.
- `Tests/AloudTests/KokoroFakes.swift` is a copy of the fakes in `Tests/KokoroTests/KokoroVoiceProviderTests.swift` and must be changed in step with them, in the same commit.
- Every commit passes `make check` and `make test`. No em dash in any file (plain dash). One sentence per line in Markdown. No co-author line in commits.
- Commit messages follow the repo's form: a sentence in the present tense, or a lower-case `docs:` prefix for documentation.
- `swift format lint --strict` runs in `make check`; run `swift format --in-place --recursive Sources Tests` before committing if lint complains. Indentation is four spaces, line length 110.
- The user's own Aloud (pid of `.build/Aloud.app`) is never killed or relaunched. In-app checks use a separate copy, as `~/.claude/projects/-Users-kevindazoo-aloud/memory/aloud-qa-isolation.md` describes.

## Facts checked before writing this plan

- `KokoroTTS.prepare(_:voice:options:) throws -> [KokoroPreparedInput]` is public; each input's `text: String?` is the chunk's text, whitespace-normalised. `KokoroTTS.synthesize` re-runs `prepare` on its text, so rendering a chunk's text alone renders that one chunk.
- `KokoroTTS.synthesize` joins chunks with a 5 ms crossfade and adds no silence; the 0.35 s lead and 0.40 s tail are the model's own output, present on every render, and `suppressPunctuationTokenAudio` zeroes punctuation frames, so silence in a render is at or within a few thousandths of zero.
- `AVAudioPlayerNode.scheduleBuffer` queues buffers in order; `play()` on a node already playing is a no-op; `stop()` drops everything queued and every pending completion is then called with the node stopped, which the existing generation guard in `KokoroPlayback` already swallows.
- A `Task { }` created inside a `@MainActor` method inherits main-actor isolation, so its body may touch the class's state; `await task.value` is not interrupted by the awaiting task's own cancellation, so a cancelled task chained behind another finishes when that one does and then returns nil.
- `Duration.seconds` is a public extension in `Sources/Speech/Timeline.swift`.
- `Tests/AloudTests/AppModelTests.swift` constructs `FakeEngine()` and `FakePlayback()` and never reads `playback.played`.
- `KokoroVoiceProviderTests` reads `playback.played.first?.volume`, `playback.played.last?.rate` and `playback.played.count`; the first two move to `playback.volumes` and `playback.rates`.

## File structure

- Create `Sources/Kokoro/Silence.swift`: the trim.
- Create `Sources/Kokoro/SentenceRender.swift`: one sentence's ordered render.
- Modify `Sources/Kokoro/KokoroEngine.swift`: `chunks(of:)` on the protocol and the actor; trimmed `synthesize`; one error mapper.
- Modify `Sources/Kokoro/KokoroPlayback.swift`: `enqueue` replaces `play`.
- Modify `Sources/Kokoro/KokoroVoiceProvider.swift`: chunked speak, seam, stretch, chained prepare.
- Create `Tests/KokoroTests/SilenceTests.swift`, `Tests/KokoroTests/SentenceRenderTests.swift`.
- Modify `Tests/KokoroTests/KokoroVoiceProviderTests.swift` (fakes and tests), `Tests/AloudTests/KokoroFakes.swift` (fakes), `Tests/KokoroTests/KokoroIntegrationTests.swift`.

---

### Task 1: Silence.trim

**Files:**
- Create: `Sources/Kokoro/Silence.swift`
- Test: `Tests/KokoroTests/SilenceTests.swift`

**Interfaces:**
- Produces: `enum Silence { static let threshold: Float; static let margin: Int; static func trim(_ samples: [Float], threshold: Float = threshold, margin: Int = margin) -> [Float] }`, internal to `Kokoro`.

- [ ] **Step 1: Write the failing tests**

```swift
import Testing

@testable import Kokoro

@Suite struct SilenceTests {
    /// Silence is anything under the threshold; `margin` samples of it are kept on
    /// each side of the speech.
    @Test func trimsTheSilenceAroundTheSpeechAndKeepsAMargin() {
        let quiet = [Float](repeating: 0.001, count: 100)
        let loud = [Float](repeating: 0.5, count: 10)
        let trimmed = Silence.trim(quiet + loud + quiet, threshold: 0.002, margin: 3)
        #expect(trimmed.count == 16)
        #expect(trimmed[0] == 0.001)
        #expect(trimmed[3] == 0.5)
        #expect(trimmed[12] == 0.5)
        #expect(trimmed[15] == 0.001)
    }

    /// Speech that starts or ends at the edge has less than a margin of silence there,
    /// and what there is comes back rather than reading past the ends.
    @Test func theMarginIsClampedAtTheEnds() {
        let loud = [Float](repeating: 0.5, count: 5)
        #expect(Silence.trim(loud, threshold: 0.002, margin: 3) == loud)
        #expect(Silence.trim([0, 0] + loud, threshold: 0.002, margin: 3).count == 7)
    }

    /// Nothing above the threshold is nothing to hear.
    @Test func allSilenceComesBackEmpty() {
        #expect(Silence.trim([Float](repeating: 0.001, count: 50), threshold: 0.002, margin: 3).isEmpty)
        #expect(Silence.trim([], threshold: 0.002, margin: 3).isEmpty)
    }

    /// Negative samples count as loud too.
    @Test func amplitudeIsAbsolute() {
        #expect(Silence.trim([0, 0, -0.5, 0, 0], threshold: 0.002, margin: 1) == [0, -0.5, 0])
    }

    /// The defaults are the measured ones: the model's silence sits within a few
    /// thousandths of zero, and 30 ms at 24 kHz clips no onset.
    @Test func theDefaultsAreTheMeasuredOnes() {
        #expect(Silence.threshold == 0.002)
        #expect(Silence.margin == 720)
    }
}
```

- [ ] **Step 2: Run the tests to verify they fail**

Run: `swift test --filter SilenceTests`
Expected: FAIL to compile, "cannot find 'Silence' in scope"

- [ ] **Step 3: Write the implementation**

```swift
import Foundation

/// The silence the model renders around every piece of speech: about 0.35 s before the
/// first word and 0.4 s after the last, measured on 2026-09-15 across forty sentences of
/// a real document at 1.75x. Left in, every seam between two chunks of one sentence was
/// a 0.75 s stop, and the pause between two sentences was that on top of the one the
/// reader set. So every render is trimmed to its speech, and the silences the reader
/// hears are the ones the app chooses: the seam beat and the reader's own pause.
enum Silence {
    /// Below this a sample is silence. The model's own silence is within a few
    /// thousandths of zero, and the quietest speech sits well above it.
    static let threshold: Float = 0.002
    /// How much of the surrounding silence stays on each side of the speech, in samples
    /// at 24 kHz: 30 ms, enough that no onset or decay is clipped.
    static let margin = 720

    /// `samples` cut down to the speech in them, with up to `margin` samples of the
    /// silence around it kept on each side. All silence comes back empty.
    static func trim(_ samples: [Float], threshold: Float = threshold, margin: Int = margin) -> [Float] {
        guard let first = samples.firstIndex(where: { abs($0) >= threshold }),
            let last = samples.lastIndex(where: { abs($0) >= threshold })
        else { return [] }
        return Array(samples[max(0, first - margin)...min(samples.count - 1, last + margin)])
    }
}
```

- [ ] **Step 4: Run the tests to verify they pass**

Run: `swift test --filter SilenceTests`
Expected: 5 tests pass

- [ ] **Step 5: Commit**

```bash
git add Sources/Kokoro/Silence.swift Tests/KokoroTests/SilenceTests.swift
git commit -m "Silence.trim cuts a render down to its speech"
```

---

### Task 2: The engine lists a sentence's chunks and trims what it renders

**Files:**
- Modify: `Sources/Kokoro/KokoroEngine.swift` (the protocol at lines 19-26, `synthesize` at lines 250-277)
- Modify: `Tests/KokoroTests/KokoroVoiceProviderTests.swift` (`FakeEngine`, lines 8-55)
- Modify: `Tests/AloudTests/KokoroFakes.swift` (`FakeEngine`, lines 55-102)
- Modify: `Tests/KokoroTests/KokoroIntegrationTests.swift`

**Interfaces:**
- Produces: `KokoroSynthesizing.chunks(of text: String, voice: String, speed: Double) async throws -> [String]`. `synthesize` keeps its signature and now returns trimmed samples.
- Produces, for tests: `FakeEngine.chunks(of:voice:speed:)` splits the text on `" | "` and records each text in `chunkCalls: [String]`; `FakeEngine.hold(_ text: String? = nil)` holds the next `synthesize` call, or the next one for `text` when given; `FakeEngine.setFailTexts(_ texts: Set<String>)` makes `synthesize` throw `.synthesis("failed")` for those texts.

- [ ] **Step 1: Extend the fake engine, in both copies**

In `Tests/KokoroTests/KokoroVoiceProviderTests.swift`, replace the whole `FakeEngine` actor (lines 7-55) with:

```swift
/// An engine that answers from a table and can be told to fail or to take its time.
/// Its chunks are the text split on " | ", so a test writes "One, | two." to get two.
actor FakeEngine: KokoroSynthesizing {
    struct Call: Equatable { let text: String; let voice: String; let speed: Double }
    var calls: [Call] = []
    var chunkCalls: [String] = []
    var loads: [URL] = []
    /// The voice each load was told to warm in.
    var loadVoices: [String] = []
    var unloads = 0
    var failLoad: String?
    var failSynthesis: KokoroEngineError?
    /// Texts whose synthesis fails, so one chunk of a sentence can fail while the rest render.
    var failTexts: Set<String> = []
    var gate: CheckedContinuation<Void, Never>?
    var holdNext = false
    /// When set, only a synthesis of this text is held.
    var holdText: String?
    var loadGate: CheckedContinuation<Void, Never>?
    var holdLoadNext = false

    func load(root: URL, cache: URL, voice: String) async throws {
        loads.append(root)
        loadVoices.append(voice)
        if holdLoadNext {
            holdLoadNext = false
            await withCheckedContinuation { loadGate = $0 }
        }
        if let failLoad { throw KokoroEngineError.load(failLoad) }
    }
    func chunks(of text: String, voice: String, speed: Double) async throws -> [String] {
        chunkCalls.append(text)
        if let failSynthesis { throw failSynthesis }
        return text.components(separatedBy: " | ")
    }
    func synthesize(_ text: String, voice: String, speed: Double) async throws -> [Float] {
        calls.append(Call(text: text, voice: voice, speed: speed))
        if holdNext, holdText == nil || holdText == text {
            holdNext = false
            holdText = nil
            await withCheckedContinuation { gate = $0 }
            try Task.checkCancellation()
        }
        if let failSynthesis { throw failSynthesis }
        if failTexts.contains(text) { throw KokoroEngineError.synthesis("failed") }
        return [Float](repeating: 0.1, count: text.count)
    }
    func unload() { unloads += 1 }
    func release() {
        gate?.resume()
        gate = nil
    }
    /// Holds the next synthesis, or the next synthesis of `text` when one is named.
    func hold(_ text: String? = nil) {
        holdNext = true
        holdText = text
    }
    /// The same for the load, so a test can unload while the models are still arriving.
    func holdLoad() { holdLoadNext = true }
    func releaseLoad() {
        loadGate?.resume()
        loadGate = nil
    }
    func setFailLoad(_ s: String?) { failLoad = s }
    func setFailSynthesis(_ e: KokoroEngineError?) { failSynthesis = e }
    func setFailTexts(_ texts: Set<String>) { failTexts = texts }
}
```

In `Tests/AloudTests/KokoroFakes.swift`, replace the `FakeEngine` actor (lines 54-102) with the same text, keeping the comment line above it (`/// An engine that answers from a table and can be told to fail or to take its time.` is the first line of the block above; the file's own header comment at lines 6-8 stays).

- [ ] **Step 2: Add the gated integration assertions**

In `Tests/KokoroTests/KokoroIntegrationTests.swift`, inside `theRealEngineSpeaksASentence`, replace the `for voice in ["af_bella", "bm_fable"] { ... }` loop (lines 28-37) with:

```swift
        for voice in ["af_bella", "bm_fable"] {
            let samples = try await engine.synthesize(
                "Nobody really teaches you research.", voice: voice, speed: 1)
            let seconds = Double(samples.count) / KokoroPlayback.sampleRate
            let finite = samples.allSatisfy(\.isFinite)
            let audible = samples.contains { abs($0) > 0.01 }
            #expect(seconds > 1 && seconds < 5, "\(voice)")
            #expect(finite, "\(voice)")
            #expect(audible, "\(voice)")
            // Trimmed: the model's 0.35 s lead and 0.4 s tail are gone, and the speech
            // starts and ends within the margin.
            let loud = { (x: Float) in abs(x) >= Silence.threshold }
            #expect(samples.prefix(Silence.margin + 1).contains(where: loud), "\(voice) lead")
            #expect(samples.suffix(Silence.margin + 1).contains(where: loud), "\(voice) tail")
        }
        // A sentence past the model's shape is several chunks, their texts are the
        // sentence, and each renders on its own as the one chunk it is.
        let chunks = try await engine.chunks(of: Self.longestSentence, voice: "af_bella", speed: 1)
        #expect(chunks.count > 1, "\(chunks)")
        #expect(chunks.joined(separator: " ") == Self.longestSentence, "\(chunks)")
        for chunk in chunks {
            #expect(try await engine.chunks(of: chunk, voice: "af_bella", speed: 1) == [chunk])
            let samples = try await engine.synthesize(chunk, voice: "af_bella", speed: 1)
            #expect(samples.prefix(Silence.margin + 1).contains { abs($0) >= Silence.threshold }, chunk)
        }
        #expect(try await engine.chunks(of: Self.shortSentence, voice: "af_bella", speed: 1) == [Self.shortSentence])
```

- [ ] **Step 3: Run the fast tests to verify they fail to compile**

Run: `swift build --build-tests 2>&1 | grep error: | head`
Expected: `FakeEngine` does not conform to `KokoroSynthesizing` is not reported yet (the protocol lacks `chunks`), but the integration test fails with "value of type 'KokoroEngine' has no member 'chunks'"

- [ ] **Step 4: Add `chunks(of:)` to the protocol and the actor, and trim `synthesize`**

In `Sources/Kokoro/KokoroEngine.swift`, replace the protocol (lines 18-26) with:

```swift
/// The engine as the provider sees it, so a fake can stand in for it.
public protocol KokoroSynthesizing: Actor {
    /// `voice` is the voice the prewarm should use: the one the reader picked, because a
    /// voice this process has not spoken in costs about a third of a second on its first
    /// sentence, and the prewarm is where that belongs.
    func load(root: URL, cache: URL, voice: String) async throws
    /// The pieces the SDK renders `text` in, in order: one for a sentence that fits the
    /// model's shape, several for one that does not. Each is a text `synthesize` renders
    /// as exactly one piece, so a sentence can be rendered and heard piece by piece.
    func chunks(of text: String, voice: String, speed: Double) async throws -> [String]
    /// The samples of `text`, trimmed to the speech in them.
    func synthesize(_ text: String, voice: String, speed: Double) async throws -> [Float]
    func unload()
}
```

Replace `synthesize` (lines 250-277) with:

```swift
    /// The SDK's own split of a sentence: `prepare` returns one input per chunk, and its
    /// text is what `synthesize` re-prepares into that one chunk. Rendering the chunks of a
    /// long sentence one at a time is what lets the first be heard while the rest render,
    /// and the seams between them be silences the app chose rather than the model's.
    public func chunks(of text: String, voice: String, speed: Double) async throws -> [String] {
        guard let tts else { throw KokoroEngineError.notLoaded }
        do {
            return try await tts.prepare(
                text, voice: KokoroVoiceID(voice), options: KokoroSynthesisOptions(speed: Float(speed))
            ).compactMap(\.text)
        } catch {
            throw Self.mapped(error)
        }
    }

    /// Trimmed to the speech: the model puts about 0.35 s of silence before the first
    /// word and 0.4 s after the last, and `Silence` says why that is cut.
    public func synthesize(_ text: String, voice: String, speed: Double) async throws -> [Float] {
        guard let tts else { throw KokoroEngineError.notLoaded }
        let audio: KokoroAudio
        do {
            audio = try await tts.synthesize(
                text, voice: KokoroVoiceID(voice), options: KokoroSynthesisOptions(speed: Float(speed)))
        } catch {
            throw Self.mapped(error)
        }
        guard audio.sampleRate == Int(KokoroPlayback.sampleRate) else {
            throw KokoroEngineError.synthesis("unexpected sample rate \(audio.sampleRate)")
        }
        return Silence.trim(audio.samples)
    }

    /// The SDK's errors as the rest of the app sees them.
    private static func mapped(_ error: Error) -> KokoroEngineError {
        switch error {
        case is CancellationError: .cancelled
        case KokoroError.synthesisCancelled: .cancelled
        case KokoroError.emptyText, KokoroError.emptyPhonemizerOutput: .nothingToSay
        case KokoroError.inaudibleChunk: .nothingToSay
        // The SDK maps its own text-processing errors onto `KokoroError` but lets the
        // phonemizer's own emptiness through untouched, so a line of "***" - a Markdown
        // rule - arrives here rather than as `emptyPhonemizerOutput`. It is the same
        // nothing, and a reading must not stall on it.
        case KokoroPhonemizerError.emptyOutput: .nothingToSay
        default: .synthesis(error.localizedDescription)
        }
    }
```

- [ ] **Step 5: Build and run the fast suites**

Run: `make check && swift test --filter 'KokoroVoiceProviderTests|SilenceTests|KokoroEnginePrewarmTests|AppModelTests'`
Expected: build clean, all pass

- [ ] **Step 6: Run the gated integration test against the installed bundle**

Run: `ALOUD_KOKORO_BUNDLE="$HOME/Library/Application Support/Aloud/Kokoro/2" swift test --filter KokoroIntegrationTests/theRealEngineSpeaksASentence`
Expected: PASS. If `chunks.joined(separator: " ") == longestSentence` fails, print the chunks, check that the SDK only normalised whitespace, and relax that one expectation to compare `chunks.joined(separator: " ").split(separator: " ")` against the sentence's words; do not change the engine.

- [ ] **Step 7: Commit**

```bash
git add Sources/Kokoro/KokoroEngine.swift Tests/KokoroTests/KokoroVoiceProviderTests.swift Tests/AloudTests/KokoroFakes.swift Tests/KokoroTests/KokoroIntegrationTests.swift
git commit -m "The engine lists a sentence's chunks and trims the silence around a render"
```

---

### Task 3: SentenceRender

**Files:**
- Create: `Sources/Kokoro/SentenceRender.swift`
- Test: `Tests/KokoroTests/SentenceRenderTests.swift`

**Interfaces:**
- Consumes: `KokoroSynthesizing.chunks(of:voice:speed:)` and `synthesize` from Task 2; `KokoroVoiceProvider.CacheKey` (exists, `struct CacheKey: Equatable { let text: String; let voice: String; let speed: Double }`).
- Produces: `@MainActor final class SentenceRender { let key: KokoroVoiceProvider.CacheKey; let all: Task<Void, Never>; init(key:engine:after:); var chunks: [String]? { get async }; func samples(ofChunk i: Int) async -> [Float]?; func cancel() }`.

- [ ] **Step 1: Write the failing tests**

```swift
import Foundation
import Testing

@testable import Kokoro

@Suite @MainActor struct SentenceRenderTests {
    typealias Key = KokoroVoiceProvider.CacheKey

    /// The chunks are the engine's, rendered in order, and every one is rendered without
    /// being asked for: the whole sentence is what a render ahead is for.
    @Test func rendersEveryChunkInOrder() async throws {
        let engine = FakeEngine()
        let r = SentenceRender(key: Key(text: "One, | two, | three.", voice: "af_bella", speed: 1), engine: engine, after: nil)
        #expect(await r.chunks == ["One,", "two,", "three."])
        await r.all.value
        #expect(await engine.calls.map(\.text) == ["One,", "two,", "three."])
        #expect(await r.samples(ofChunk: 1)?.count == 4)
        #expect(await r.samples(ofChunk: 3) == nil)
    }

    /// Asking for a chunk waits for it and for nothing after it.
    @Test func aChunkIsHandedOverAsSoonAsItIsRendered() async throws {
        let engine = FakeEngine()
        await engine.hold("two.")
        let r = SentenceRender(key: Key(text: "One, | two.", voice: "af_bella", speed: 1), engine: engine, after: nil)
        #expect(await r.samples(ofChunk: 0)?.count == 4)
        #expect(await engine.calls.count == 2)
        await engine.release()
        #expect(await r.samples(ofChunk: 1)?.count == 4)
    }

    /// The engine is one actor: a render made after another waits for all of that one's
    /// chunks before it plans, so the sentence being heard never queues behind the one
    /// rendered ahead of it.
    @Test func aRenderWaitsForTheWholeOfTheOneBeforeIt() async throws {
        let engine = FakeEngine()
        await engine.hold("two.")
        let first = SentenceRender(key: Key(text: "One, | two.", voice: "af_bella", speed: 1), engine: engine, after: nil)
        let second = SentenceRender(key: Key(text: "Three.", voice: "af_bella", speed: 1), engine: engine, after: first)
        _ = await first.samples(ofChunk: 0)
        try await Task.sleep(for: .milliseconds(50))
        #expect(await engine.chunkCalls == ["One, | two."])
        await engine.release()
        #expect(await second.samples(ofChunk: 0)?.count == 6)
        #expect(await engine.calls.map(\.text) == ["One,", "two.", "Three."])
    }

    /// A cancelled render answers nil for everything and asks the engine for nothing
    /// more; one chained after it is not held up.
    @Test func cancelStopsTheQueue() async throws {
        let engine = FakeEngine()
        await engine.hold("One,")
        let r = SentenceRender(key: Key(text: "One, | two.", voice: "af_bella", speed: 1), engine: engine, after: nil)
        let next = SentenceRender(key: Key(text: "Three.", voice: "af_bella", speed: 1), engine: engine, after: r)
        _ = await r.chunks
        r.cancel()
        await engine.release()
        #expect(await r.samples(ofChunk: 0) == nil)
        #expect(await r.samples(ofChunk: 1) == nil)
        #expect(await next.samples(ofChunk: 0)?.count == 6)
        #expect(await engine.calls.map(\.text) == ["One,", "Three."])
    }

    /// A plan that fails is a sentence with nothing to say: nil chunks, nil samples.
    @Test func aFailedPlanIsNil() async throws {
        let engine = FakeEngine()
        await engine.setFailSynthesis(.nothingToSay)
        let r = SentenceRender(key: Key(text: "***", voice: "af_bella", speed: 1), engine: engine, after: nil)
        #expect(await r.chunks == nil)
        #expect(await r.samples(ofChunk: 0) == nil)
        #expect(await engine.calls.isEmpty)
    }

    /// One chunk failing is that chunk alone: the ones after it still render.
    @Test func aFailedChunkIsNilAndTheRestRender() async throws {
        let engine = FakeEngine()
        await engine.setFailTexts(["two,"])
        let r = SentenceRender(key: Key(text: "One, | two, | three.", voice: "af_bella", speed: 1), engine: engine, after: nil)
        #expect(await r.samples(ofChunk: 1) == nil)
        #expect(await r.samples(ofChunk: 2)?.count == 6)
    }
}
```

- [ ] **Step 2: Run the tests to verify they fail**

Run: `swift test --filter SentenceRenderTests`
Expected: FAIL to compile, "cannot find 'SentenceRender' in scope"

- [ ] **Step 3: Write the implementation**

```swift
import Foundation
import os

/// One sentence's render: the SDK's chunk list, then each chunk's samples, in order.
///
/// The engine is one actor and the SDK runs a whole chunk without suspending, so the
/// order renders are asked for is the order they happen in. Every chunk here is queued
/// behind the one before it, and the plan behind the whole of the render before this
/// one, so two sentences never interleave and the sentence being heard is never put
/// behind the one rendered ahead of it. Everything is rendered without being asked for:
/// `samples(ofChunk:)` only waits.
@MainActor final class SentenceRender {
    let key: KokoroVoiceProvider.CacheKey
    /// Finishes once every chunk has been rendered, failed or been cancelled. The next
    /// render waits on it before it plans.
    private(set) var all: Task<Void, Never>!
    private let engine: any KokoroSynthesizing
    private let planning: Task<[String]?, Never>
    private var renders: [Task<[Float]?, Never>] = []
    /// Set by `cancel`, so a chunk task made after it starts cancelled: the plan can land
    /// after the cancel, and `all` would otherwise queue every chunk of a dead sentence.
    private var cancelled = false
    private static let log = Logger(subsystem: "design.kevxu.aloud", category: "kokoro")

    /// `previous` is the render made before this one, whatever became of it: a cancelled
    /// one finishes at once and holds this up by nothing.
    init(key: KokoroVoiceProvider.CacheKey, engine: any KokoroSynthesizing, after previous: SentenceRender?) {
        self.key = key
        self.engine = engine
        let before = previous?.all
        let (text, voice, speed) = (key.text, key.voice, key.speed)
        planning = Task {
            await before?.value
            guard !Task.isCancelled else { return nil }
            do {
                return try await engine.chunks(of: text, voice: voice, speed: speed)
            } catch KokoroEngineError.cancelled {
                return nil
            } catch {
                Self.log.error(
                    "Kokoro could not plan a sentence: \((error as? KokoroEngineError).map(KokoroVoiceProvider.text) ?? error.localizedDescription, privacy: .public)"
                )
                return nil
            }
        }
        all = Task { [self] in
            guard let chunks = await planning.value else { return }
            render(chunks, upTo: chunks.count - 1)
            for r in renders { _ = await r.value }
        }
    }

    /// The chunk texts, or nil when the plan failed or was cancelled.
    var chunks: [String]? {
        get async { await planning.value }
    }

    /// The samples of chunk `i`, once rendered; nil for a chunk that failed, was cancelled
    /// or does not exist.
    func samples(ofChunk i: Int) async -> [Float]? {
        guard let chunks = await planning.value, i >= 0, i < chunks.count else { return nil }
        render(chunks, upTo: i)
        return await renders[i].value
    }

    /// Queues the renders up to chunk `i`, each behind the one before it. Idempotent: the
    /// first of `all` and `samples(ofChunk:)` to run after the plan lands does the work.
    private func render(_ chunks: [String], upTo i: Int) {
        while renders.count <= i {
            let text = chunks[renders.count]
            let previous = renders.last
            let (voice, speed, engine) = (key.voice, key.speed, engine)
            let task = Task<[Float]?, Never> {
                _ = await previous?.value
                guard !Task.isCancelled else { return nil }
                do {
                    return try await engine.synthesize(text, voice: voice, speed: speed)
                } catch KokoroEngineError.cancelled {
                    return nil
                } catch {
                    Self.log.error(
                        "Kokoro could not speak a chunk: \((error as? KokoroEngineError).map(KokoroVoiceProvider.text) ?? error.localizedDescription, privacy: .public)"
                    )
                    return nil
                }
            }
            if cancelled { task.cancel() }
            renders.append(task)
        }
    }

    func cancel() {
        cancelled = true
        planning.cancel()
        renders.forEach { $0.cancel() }
        all.cancel()
    }
}
```

- [ ] **Step 4: Run the tests to verify they pass**

Run: `swift test --filter SentenceRenderTests`
Expected: 6 tests pass. If `aChunkIsHandedOverAsSoonAsItIsRendered` sees `calls.count == 1`, the second chunk's task has not reached the engine yet; replace that expectation with `#expect(await eventually { await engine.calls.count == 2 })` using the same `eventually` helper `KokoroVoiceProviderTests` has, copied into this suite.

- [ ] **Step 5: Commit**

```bash
git add Sources/Kokoro/SentenceRender.swift Tests/KokoroTests/SentenceRenderTests.swift
git commit -m "SentenceRender renders a sentence's chunks in order, behind the render before it"
```

---

### Task 4: The provider speaks chunk by chunk through a queueing playback

**Files:**
- Modify: `Sources/Kokoro/KokoroPlayback.swift`
- Modify: `Sources/Kokoro/KokoroVoiceProvider.swift`
- Modify: `Tests/KokoroTests/KokoroVoiceProviderTests.swift` (`FakePlayback` and the tests)
- Modify: `Tests/AloudTests/KokoroFakes.swift` (`FakePlayback`)

**Interfaces:**
- Consumes: `SentenceRender` from Task 3.
- Produces: `KokoroPlaying.enqueue(_ samples: [Float], completion: @escaping @MainActor () -> Void)` in place of `play`; `KokoroVoiceProvider.seamPause: Duration`; `KokoroVoiceProvider.setRate` answers true for any speed while a sentence is in the air.
- Produces, for tests: `FakePlayback.played: [[Float]]`, `finish()` calls the oldest unfired completion.

- [ ] **Step 1: Replace `FakePlayback`, in both copies**

In `Tests/KokoroTests/KokoroVoiceProviderTests.swift` replace the `FakePlayback` class (lines 57-83 before Task 2's edit; the block from `/// Plays nothing` to its closing brace) with:

```swift
/// Plays nothing and lets the test say when each queued buffer has been heard.
@MainActor final class FakePlayback: KokoroPlaying {
    var played: [[Float]] = []
    var stops = 0
    private var completions: [@MainActor () -> Void] = []
    func enqueue(_ samples: [Float], completion: @escaping @MainActor () -> Void) {
        played.append(samples)
        completions.append(completion)
    }
    var volumes: [Double] = []
    var rates: [Double] = []
    var shutdowns = 0
    func setVolume(_ volume: Double) { volumes.append(volume) }
    func setRate(_ rate: Double) { rates.append(rate) }
    func shutdown() { shutdowns += 1 }
    /// Counts the stop and keeps the completions: a real player calls back after one,
    /// and it must be the provider's own generation guard that swallows it.
    func stop() { stops += 1 }
    /// The oldest buffer still queued has been heard.
    func finish() {
        guard !completions.isEmpty else { return }
        completions.removeFirst()()
    }
}
```

Make the same replacement in `Tests/AloudTests/KokoroFakes.swift`.

- [ ] **Step 2: Rewrite the provider tests that read the old playback**

In `Tests/KokoroTests/KokoroVoiceProviderTests.swift`:

In `speakSynthesizesPlaysPausesAndFinishes`, replace `#expect(playback.played.first?.volume == 0.5)` with `#expect(playback.volumes == [0.5])`.

In `previewInterruptsAndSpeaksTheSentence`, keep the test as it is; `playback.played.count == 2` still holds.

Replace `aRateChangeAboveTheCapKeepsThePreparedSentence`'s two `rate` expectations: `#expect(playback.rates == [1.5])` becomes `#expect(playback.rates == [1.25, 1.5])` (the sentence was started with a stretch of 2.5 / 2), and `#expect(playback.played.last?.rate == 1.5)` becomes `#expect(playback.rates.last == 1.5)`.

In `aRateAboveTheCapIsSplitBetweenTheEngineAndThePlayback`, replace `#expect(playback.played.last?.rate == 1.5)` with `#expect(playback.rates.last == 1.5)` and `#expect(playback.played.last?.rate == 1)` with `#expect(playback.rates.last == 1)`.

In `aRateChangeDuringARenderReachesThatSentence`, replace `#expect(playback.played.last?.rate == 1.5)` with `#expect(playback.rates.last == 1.5)`.

In `setVolumeReachesThePlaybackWithoutTheEngine`, the node's level is now set before a sentence's first buffer, so replace `#expect(playback.volumes == [0.25])` with `#expect(playback.volumes == [1, 0.25])` and `#expect(playback.played.last?.volume == 0.5)` with `#expect(playback.volumes.last == 0.5)`.

Replace `aRateChangeAcrossTheCapIsRefused` entirely with:

```swift
    /// A speed change while a sentence is in the air is heard where the reader is: the
    /// rest of the sentence is stretched by the new speed over the rendered one, and
    /// nothing is stopped or rendered again. Before the first sentence there is nothing
    /// to stretch, and the player speaks at the new speed when it starts.
    @Test func aRateChangeMidSentenceStretchesTheRestOfIt() async throws {
        let (p, engine, playback, _, store) = try make()
        await store.start()
        p.warm()
        await p.warmTask?.value
        #expect(!p.setRate(.x3), "nothing is being spoken")
        p.speak("One.", voice: bella, rate: .x1, pause: .zero, volume: 1, onWord: { _ in }, onFinish: {})
        #expect(await until { playback.played.count == 1 })
        #expect(p.setRate(.x15))
        #expect(playback.rates.last == 1.5)
        #expect(playback.stops == 0)
        #expect(await engine.calls.count == 1)
        // Down as well as up, and past the cap: 3x over a sentence rendered at 1x.
        #expect(p.setRate(.x05))
        #expect(playback.rates.last == 0.5)
        #expect(p.setRate(.x3))
        #expect(playback.rates.last == 3)
        // The next sentence is rendered at the speed the reader is at, with no stretch.
        p.speak("Two.", voice: bella, rate: .x3, pause: .zero, volume: 1, onWord: { _ in }, onFinish: {})
        #expect(await until { playback.played.count == 2 })
        #expect(await engine.calls.last?.speed == 2)
        #expect(playback.rates.last == 1.5)
    }
```

Replace `aPrefetchWaitsForTheSentenceBeingSpoken` with:

```swift
    /// The engine is one actor, so a prefetch started while the reader's own sentence is
    /// being rendered would put that sentence behind it. The prefetch is chained after
    /// the whole of the sentence in the air, then runs, once.
    @Test func aPrefetchRendersAfterTheSentenceBeingSpoken() async throws {
        let (p, engine, playback, _, store) = try make()
        await store.start()
        p.warm()
        await p.warmTask?.value
        await engine.hold("two.")
        p.speak("One, | two.", voice: bella, rate: .x1, pause: .zero, volume: 1, onWord: { _ in }, onFinish: {})
        p.prepare("Three.", voice: bella, rate: .x1)
        #expect(await until { playback.played.count == 1 })
        try await Task.sleep(for: .milliseconds(50))
        #expect(await engine.calls.map(\.text) == ["One,", "two."])
        await engine.release()
        #expect(await until { playback.played.count == 2 })
        #expect(await eventually { await engine.calls.map(\.text) == ["One,", "two.", "Three."] })
    }
```

Add these tests at the end of the suite, before its closing brace:

```swift
    /// A sentence past the model's shape is heard from its first chunk: each chunk is
    /// queued the moment it is rendered, with the seam beat after every one but the
    /// last, and the sentence is finished only once the last queued buffer is heard.
    @Test func aLongSentenceIsQueuedChunkByChunkWithASeamBetween() async throws {
        let (p, engine, playback, held, store) = try make()
        await store.start()
        p.warm()
        await p.warmTask?.value
        await engine.hold("two,")
        var finished = 0
        p.speak(
            "One, | two, | three.", voice: bella, rate: .x1, pause: .milliseconds(200), volume: 1,
            onWord: { _ in }, onFinish: { finished += 1 })
        #expect(await until { playback.played.count == 1 })
        #expect(playback.played[0].count == 4 + KokoroVoiceProvider.seam.count)
        #expect(playback.played[0].suffix(KokoroVoiceProvider.seam.count).allSatisfy { $0 == 0 })
        await engine.release()
        #expect(await until { playback.played.count == 3 })
        #expect(playback.played[2].count == 6)
        playback.finish()
        playback.finish()
        #expect(held.asked.isEmpty)
        playback.finish()
        #expect(await until { held.asked == [.milliseconds(200)] })
        held.release()
        await p.pauseTask?.value
        #expect(finished == 1)
    }

    /// The seam is the length of a spoken comma.
    @Test func theSeamIsOneHundredAndEightyMilliseconds() {
        #expect(KokoroVoiceProvider.seamPause == .milliseconds(180))
        #expect(KokoroVoiceProvider.seam.count == 4320)
    }

    /// A chunk that fails is that chunk alone: the rest of the sentence is heard and the
    /// sentence finishes. A sentence whose every chunk fails finishes silently, so the
    /// reading never stalls.
    @Test func aFailedChunkIsSkippedAndTheSentenceStillFinishes() async throws {
        let (p, engine, playback, held, store) = try make()
        await store.start()
        p.warm()
        await p.warmTask?.value
        await engine.setFailTexts(["two,"])
        var finished = 0
        p.speak(
            "One, | two, | three.", voice: bella, rate: .x1, pause: .milliseconds(50), volume: 1,
            onWord: { _ in }, onFinish: { finished += 1 })
        #expect(await until { playback.played.count == 2 })
        #expect(playback.played[1].count == 6)
        playback.finish()
        playback.finish()
        #expect(await until { held.asked.count == 1 })
        held.release()
        await p.pauseTask?.value
        #expect(finished == 1)
        await engine.setFailTexts(["Four."])
        p.speak(
            "Four.", voice: bella, rate: .x1, pause: .milliseconds(50), volume: 1,
            onWord: { _ in }, onFinish: { finished += 1 })
        #expect(await until { held.asked.count == 2 })
        held.release()
        await p.pauseTask?.value
        #expect(finished == 2)
        #expect(playback.played.count == 2)
    }

    /// A speed change mid-sentence re-renders the sentence prepared ahead at the new
    /// engine speed, so the boundary is still a hit. Within the capped band it is left
    /// alone, since the engine speed is the same.
    @Test func aRateChangeRebuildsThePreparedSentenceAtTheNewSpeed() async throws {
        let (p, engine, playback, _, store) = try make()
        await store.start()
        p.warm()
        await p.warmTask?.value
        p.speak("One.", voice: bella, rate: .x1, pause: .zero, volume: 1, onWord: { _ in }, onFinish: {})
        #expect(await until { playback.played.count == 1 })
        p.prepare("Two.", voice: bella, rate: .x1)
        #expect(await eventually { await engine.calls.count == 2 })
        #expect(p.setRate(.x15))
        #expect(await eventually { await engine.calls.count == 3 })
        #expect(await engine.calls.last == .init(text: "Two.", voice: "af_bella", speed: 1.5))
        p.speak("Two.", voice: bella, rate: .x15, pause: .zero, volume: 1, onWord: { _ in }, onFinish: {})
        #expect(await until { playback.played.count == 2 })
        #expect(await engine.calls.count == 3)
        #expect(playback.rates.last == 1)
    }

    /// The level and the stretch are set on the node before a sentence's first buffer,
    /// and a level change while the sentence is still rendering reaches it.
    @Test func theNodeIsSetBeforeTheFirstBuffer() async throws {
        let (p, engine, playback, _, store) = try make()
        await store.start()
        p.warm()
        await p.warmTask?.value
        await engine.hold()
        p.speak("One.", voice: bella, rate: .x25, pause: .zero, volume: 0.4, onWord: { _ in }, onFinish: {})
        #expect(await eventually { await engine.calls.count == 1 })
        #expect(playback.volumes == [0.4])
        #expect(playback.rates == [1.25])
        #expect(p.setVolume(0.7))
        await engine.release()
        #expect(await until { playback.played.count == 1 })
        #expect(playback.volumes == [0.4, 0.7])
    }

    /// Stop cancels the sentence in the air and the one rendered ahead, and a render
    /// after the stop does not wait on either.
    @Test func stopCancelsBothRenders() async throws {
        let (p, engine, playback, _, store) = try make()
        await store.start()
        p.warm()
        await p.warmTask?.value
        await engine.hold("two,")
        p.speak("One, | two, | three.", voice: bella, rate: .x1, pause: .zero, volume: 1, onWord: { _ in }, onFinish: {})
        p.prepare("Four.", voice: bella, rate: .x1)
        #expect(await until { playback.played.count == 1 })
        p.stop()
        await engine.release()
        p.speak("Five.", voice: bella, rate: .x1, pause: .zero, volume: 1, onWord: { _ in }, onFinish: {})
        #expect(await until { playback.played.count == 2 })
        #expect(await engine.calls.map(\.text) == ["One,", "two,", "Five."])
    }
```

- [ ] **Step 3: Run the provider tests to verify they fail to compile**

Run: `swift build --build-tests 2>&1 | grep error: | head`
Expected: errors in `KokoroVoiceProvider.swift` ("value of type 'any KokoroPlaying' has no member 'play'" is not yet reported; instead `FakePlayback` does not conform to `KokoroPlaying` because the protocol still requires `play`)

- [ ] **Step 4: Replace `play` with `enqueue` in the playback**

In `Sources/Kokoro/KokoroPlayback.swift`, replace the protocol (lines 4-19) with:

```swift
/// Queues buffers of samples and says when each has been heard, so a fake can stand in.
@MainActor
public protocol KokoroPlaying: AnyObject {
    /// Queues one buffer behind whatever is queued, starting the device if it is idle, and
    /// calls back once that buffer has been heard. Nothing already queued is touched, so
    /// a sentence can be heard chunk by chunk as its chunks are rendered.
    func enqueue(_ samples: [Float], completion: @escaping @MainActor () -> Void)
    /// The level of whatever is playing and queued, changed where it stands.
    func setVolume(_ volume: Double)
    /// The time stretch of whatever is playing and queued, changed where it stands: how a
    /// speed the model did not render is made up, and how a speed change mid-sentence is
    /// heard without rendering the sentence again. 1 is the samples as rendered.
    func setRate(_ rate: Double)
    /// Drops everything queued.
    func stop()
    /// Stops and gives the audio device back, for a reader who has picked another engine
    /// and will not be spoken to by this one again until they pick it back.
    func shutdown()
}
```

Replace the class comment and `play` (lines 21-84) with:

```swift
/// An audio engine with one player node at the model's 24 kHz mono, through a time
/// stretch. Buffers queue on the node in the order they arrive. A device change stops the
/// engine out from under it; the next `enqueue` restarts it on the new device. The pause
/// on that same change is the app model's, through `OutputDeviceWatcher`, not this
/// class's.
@MainActor
public final class KokoroPlayback: KokoroPlaying {
    /// Nonisolated so `KokoroEngine`, a plain actor, can check the SDK's output against
    /// it without crossing to the main actor for a constant.
    public nonisolated static let sampleRate: Double = 24000

    private let engine = AVAudioEngine()
    private let node = AVAudioPlayerNode()
    /// The speed the model could not deliver, and the rest of a sentence at a speed the
    /// reader changed to mid-way. It sits between the player node and the mixer at all
    /// times, at rate 1 whenever nothing is being stretched, so the graph does not have
    /// to be rewired when the reader changes speed.
    private let timePitch = AVAudioUnitTimePitch()
    private let format = AVAudioFormat(standardFormatWithSampleRate: KokoroPlayback.sampleRate, channels: 1)!
    /// A completion from a buffer that was dropped by a stop is not one the caller wants.
    private var generation = 0

    public init() {
        engine.attach(node)
        engine.attach(timePitch)
        engine.connect(node, to: timePitch, format: format)
        engine.connect(timePitch, to: engine.mainMixerNode, format: format)
    }

    public func enqueue(_ samples: [Float], completion: @escaping @MainActor () -> Void) {
        let gen = generation
        // An empty buffer is heard at once. The caller keeps its own order and never
        // hands one over, so this is only a guard against scheduling nothing.
        guard !samples.isEmpty else {
            completion()
            return
        }
        if !engine.isRunning {
            do {
                try engine.start()
            } catch {
                completion()
                return
            }
        }
        guard
            let buffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: AVAudioFrameCount(samples.count)),
            let channel = buffer.floatChannelData?[0]
        else {
            completion()
            return
        }
        samples.withUnsafeBufferPointer { channel.update(from: $0.baseAddress!, count: samples.count) }
        buffer.frameLength = AVAudioFrameCount(samples.count)
        node.scheduleBuffer(buffer, completionCallbackType: .dataPlayedBack) { _ in
            Task { @MainActor [weak self] in
                guard let self, gen == self.generation else { return }
                completion()
            }
        }
        // A no-op on a node already playing; what it is for is the first buffer after a
        // stop or a device change, when the node is idle.
        node.play()
    }
```

Keep `setVolume`, `setRate`, `stop`, `shutdown`, `level`, `stretchRange` and `stretch` as they are.

- [ ] **Step 5: Rewrite the provider**

Replace the whole of `Sources/Kokoro/KokoroVoiceProvider.swift` from the class declaration through `finishedRendering`/`startPendingPrepare`/`setVolume`/`setRate`/`stop`/`preview`/`warm`/`unload`/`samples(for:)`/`finish`/`cancelCurrent`/`text` with the following. `LoadFlag` at the end of the file stays.

```swift
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
        let tally = Tally()
        for i in chunks.indices {
            let samples = await render.samples(ofChunk: i)
            guard gen == generation else { return }
            guard let samples, !samples.isEmpty else { continue }
            tally.queued += 1
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
        _ tally: Tally, after pause: Duration, generation gen: Int, _ onFinish: @escaping @MainActor () -> Void
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
        playback.setRate(new.factor / renderedSpeed)
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

    private let log = Logger(subsystem: "design.kevxu.aloud", category: "kokoro")

    static func text(_ error: KokoroEngineError) -> String {
        switch error {
        case .notLoaded: "the model is not loaded"
        case .load(let s), .synthesis(let s): s
        case .cancelled: "cancelled"
        case .nothingToSay: "nothing to say"
        }
    }
}
```

- [ ] **Step 6: Build and run the Kokoro and app suites**

Run: `make check && swift test --filter 'KokoroTests|AloudTests'`
Expected: build clean; every test passes. Known places to look if one does not:
- `aPrepareBeforeTheModelsAreLoadedIsNotLost` expects `calls == ["One.", "Two."]`: the pending prepare is issued from the speak task after `start(key)`, so "One." is planned first.
- `theWarmUsesTheVoiceThatWasPicked` and `speakWarmsWhenCold` drive the cold path; `isWaitingOnLoad` must be false again before `startPendingPrepare` in `speak` runs, which it is.
- `previewInterruptsAndSpeaksTheSentence` expects `playback.stops == 1` and `played.count == 2`.
- `aLoadFailureEmptiesTheListAndReports` and `aFailedWarmStillFinishesTheSentence` do not touch the playback.

- [ ] **Step 7: Run the whole suite**

Run: `make test`
Expected: all pass

- [ ] **Step 8: Commit**

```bash
git add Sources/Kokoro/KokoroPlayback.swift Sources/Kokoro/KokoroVoiceProvider.swift Tests/KokoroTests/KokoroVoiceProviderTests.swift Tests/AloudTests/KokoroFakes.swift
git commit -m "A Kokoro sentence is heard chunk by chunk, and a speed change is heard where the reader is"
```

---

### Task 5: Measure, check in the app, and record

**Files:**
- Modify: `Tests/KokoroTests/ZZMeasureHomeTests.swift` (run, then delete)
- Modify: `docs/superpowers/specs/2026-09-15-kokoro-chunk-streaming-design.md` (the numbers after)
- Modify: `Tests/KokoroTests/KokoroIntegrationTests.swift` (a line in the wall-clock doc comment)

- [ ] **Step 1: Re-run the measurement on the reader's note**

The temporary test already exists in the working tree (untracked). Its `synthesize` calls now return trimmed audio; it reports `lead`, `silences` and `tail` per sentence.

Run: `ALOUD_MEASURE_DOC="$HOME/Documents/Aloud Notes/Home.md" ALOUD_KOKORO_BUNDLE="$HOME/Library/Application Support/Aloud/Kokoro/2" ALOUD_MEASURE_CACHE=<scratchpad>/kokoro-cache-debug ALOUD_MEASURE_LIMIT=6 swift test --filter ZZMeasureHomeTests 2>&1 | grep -E '^(MEASURE|ROW)'`
Expected: every `lead` is at most 0.03 and every `tail` at most 0.03; sentence 0 still shows its 14 internal silences, since this test calls `synthesize` on the whole sentence and the SDK still joins the chunks itself. Then, for sentence 0 only, add to the test a loop that calls `engine.chunks(of:)` and times `synthesize` per chunk, printing each chunk's wall and audio seconds, and run it again: the first chunk's wall is the wait a reader now has before the first note, in place of the 10.9 s.

- [ ] **Step 2: Delete the temporary test**

Run: `rm Tests/KokoroTests/ZZMeasureHomeTests.swift && git status --short`
Expected: the file is gone and not in the status

- [ ] **Step 3: Hear it in a separate copy of the app**

Follow `~/.claude/projects/-Users-kevindazoo-aloud/memory/aloud-qa-isolation.md`: `swift build --product Aloud`, then copy `.build/debug/Aloud` into a bundle in the scratchpad with its own `CFBundleIdentifier`, its own `CFFIXED_USER_HOME`, and inside that home a copy or symlink of `~/Library/Application Support/Aloud/Kokoro/2` and `~/Library/Caches/Aloud/Kokoro/2`, a notes folder holding a copy of `Home.md`, and `progress.json` empty. Set `KeyboardShortcuts_pasteAndPlay` false and `showMenuBar` false in its defaults, and `voiceID` to `kokoro.af_sarah` and `rateFactor` to `1.75`. Launch with `open -g -n --env CFFIXED_USER_HOME=<home> <bundle>`, open `Home.md` through the card's `Open` action and press Play through the Playback menu. In the unified log for the copy's pid, `AQME Default-Output: client starting` marks the first audio; time it against the Play press. Then press Faster through the menu twice while sentence 0 plays and confirm no `client starting` gap follows and the sentence does not restart from the top, then kill the copy with `kill -9`.
Never touch the user's own Aloud process.

- [ ] **Step 4: Record the numbers**

Append to the spec's "The problem, measured" section a subsection "After" with: the first-chunk wait for sentence 0 in place of 10.9 s, lead and tail after the trim, and the in-app press-to-audio time. In `KokoroIntegrationTests.theWallClockOfASentenceIsRecorded`'s doc comment, add one line after the table: the numbers were taken before renders were trimmed; trimming removes about 0.75 s of silence from every render and changes no wall clock.

- [ ] **Step 5: Commit**

```bash
git add docs/superpowers/specs/2026-09-15-kokoro-chunk-streaming-design.md Tests/KokoroTests/KokoroIntegrationTests.swift
git commit -m "docs: what chunk streaming measured before and after"
```

---

## What Task 5 found

- The SDK refuses a model folder reached through a symlink ("resource path escapes its root"), so the copy's home needs a real copy of `Kokoro/2` and of a compiled cache, about 1 GB for the two.
- The copy reads and writes the real `design.kevxu.aloud.qa` defaults domain, not a plist under `CFFIXED_USER_HOME`, and it carries the last copy's speed; set `rateFactor` there and read it back before launching.
- `AQME Default-Output: client starting` is an AudioQueue line and marks the Apple voice only; the Kokoro engine's `AVAudioEngine` leaves no such trace. The provider's debug lines ("speaks N chunks", "queued the first chunk", "stretches") in a live `log stream --level debug` are the timing evidence.
- Sentence 0's `AudioQueue` stop and start pairs seen on the first attempt were the Apple voice re-speaking after each press: the copy had fallen back to it when the symlinked model failed to load.

## Self-review

- Spec coverage: change 1 is Tasks 2 to 4 (`chunks`, `SentenceRender`, chunked `play`); change 2 is Task 1 and the seam in Task 4; change 3 is `setRate` in Task 4; change 4 is `SentenceRender`'s `after` chain in Task 3 and `make` in Task 4; the testing section maps to Tasks 1 to 4 and the measurement to Task 5.
- Placeholders: none; every code step carries the code.
- Types: `CacheKey` is `KokoroVoiceProvider.CacheKey` throughout; `SentenceRender.all` is `Task<Void, Never>!` and read as `previous?.all` (an optional chain over an implicitly unwrapped optional yields `Task<Void, Never>?`); `FakePlayback.played` is `[[Float]]` in Task 4 and the tests index it as such; `FakeEngine.hold(_:)` takes an optional text in Task 2 and Tasks 3 and 4 call it both ways; `KokoroVoiceProvider.seam` is `[Float]` and `seamPause` a `Duration`, both internal, read by the tests through `@testable import`.
