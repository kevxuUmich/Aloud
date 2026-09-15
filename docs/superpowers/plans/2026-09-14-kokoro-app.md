# Kokoro voices in the app implementation plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** A reader picks one of seven Kokoro voices in the voice picker, the app downloads the model bundle once, and reading proceeds as it does today with the sentence highlighted, through a second engine that runs on the Mac's Neural Engine.

**Architecture:** A new module, `Kokoro`, sits beside `Speech`: a catalogue of the seven voices, a store that owns the model's life on disk, an actor over the SDK, an `AVAudioEngine` player, and a `KokoroVoiceProvider` that conforms to the same `VoiceProvider` protocol the Apple provider does.
`Speech` gains a `prepare` hook so the next sentence is synthesized while the current one plays, and a `CompositeVoiceProvider` that routes by voice id prefix, so `Player` and `AppModel` keep one provider.
The picker gains a Kokoro section above Recommended, drawn from the catalogue and the store's state; Settings gains a row; the app gains the network entitlement.

**Tech Stack:** Swift 6.2 strict concurrency, SwiftUI and AppKit on macOS 26, Swift Testing, AVFoundation, CryptoKit, a background `URLSession`, the `KokoroTTS` product of the kokoro-coreml fork at revision `2932a26444b8deba2a6be6c0aa45c0424efaefe1`, and the `KokoroBundle` library plan 2 added for archive extraction.

**Spec:** `docs/superpowers/specs/2026-09-13-kokoro-voices-design.md`

This is plan 3 of 3.
Plan 1 produced the forks and plan 2 the archive this plan downloads.

## Global Constraints

- macOS 26 only; Swift 6 language mode with strict concurrency in every target. `Speech` stays free of the SDK so its tests stay fast and `--silent` still works.
- No number, colour, font size or duration literal in `Sources/Aloud` or `Sources/AloudUI` outside `Sources/AloudUI/Tokens.swift`; `Tests/AloudUITests/LiteralLintTests.swift` enforces the common forms. Every size, spacing and string the Kokoro section introduces goes through `Tokens.swift`.
- The seven voices, in this order, with these Aloud ids, names and language tags: `kokoro.af_bella` Bella `en-US`, `kokoro.af_sarah` Sarah `en-US`, `kokoro.am_michael` Michael `en-US`, `kokoro.am_fenrir` Fenrir `en-US`, `kokoro.bf_emma` Emma `en-GB`, `kokoro.bm_george` George `en-GB`, `kokoro.bm_fable` Fable `en-GB`. Quality is `.premium`. The prefix is `kokoro.` and the Kokoro voice id is what follows it.
- The download is pinned in one file by URL, version and SHA-256: `https://github.com/kevxuUmich/Aloud/releases/download/kokoro-models/kokoro-1.aar`, version `1`, and the SHA-256 and byte count plan 2's Task 5 printed (also in the release's `kokoro-1.aar.sha256` asset). Nothing is fetched from Hugging Face at runtime.
  Superseded after this plan ran: the final fix wave republished the models as `kokoro-2.aar`, the four-bucket bundle, and `Sources/Kokoro/KokoroRelease.swift` is where the current URL, version, SHA-256 and byte count live. `kokoro-1.aar` is still published and untouched.
- Files live at `Application Support/Aloud/Kokoro/<version>/` and `Caches/Aloud/Kokoro/<version>/`, the latter excluded from backup. Both are the app's own directories.
- The SDK is loaded with `KokoroTTS.load(resources: .directory(root, compiledModelsDirectory: cache))`; `KokoroError` is not `Sendable` and never crosses an actor boundary; the provider maps it.
- Kokoro voices highlight the sentence, never the word: `onWord` is never called.
- Copy is exactly the spec's: section header `Kokoro`; caption `Seven voices, one download of about 160 MB, runs on your Mac.` (the number is the archive size from plan 2 rounded to the nearest 5 MB); buttons `Cancel`, `Retry`, `Download`, `Remove`; failure sentences `No internet connection.`, `The download did not match what Aloud expected.`, `Not enough disk space.`
- The network client entitlement `com.apple.security.network.client` is added to `App/Aloud.entitlements` and to the entitlements block in `project.yml`, which states the sandbox keys twice on purpose.
- Every commit passes `make check` and `make test`. No em dash in any file (plain dash). One sentence per line in Markdown. No co-author line in commits.
- Commit messages follow the repo's form: a sentence in the present tense, or a lower-case `docs:` prefix for documentation.
- `swift format lint --strict` runs in `make check`; run `swift format --in-place --recursive Sources Tests` before committing if lint complains. Indentation is four spaces, line length 110.

## Facts checked before writing this plan

- `VoiceProvider` has six requirements and no default implementations; `speak`, `stop` and `preview` are `@MainActor`, and `voices`, `defaultVoice` and `refreshVoices` are nonisolated. `Player.provider` is `private let`, so a second engine must arrive through a provider that conforms to the protocol and routes.
- `Player.speakCurrent` computes the next boundary's pause before it calls `provider.speak`, which is where the prepare call for the next sentence goes. `Player.ensureVoiceIsInstalled` is the whole unavailable-voice path: membership of `provider.voices` by id, then `defaultVoice` and `onVoiceUnavailable`.
- `AppleVoiceProvider` guards late delegate callbacks by utterance identity and holds the sentence pause itself in a cancellable task. The Kokoro provider uses a generation counter for the same guard.
- `VoiceRow` is a pure `AloudUI` view of strings and closures with no busy or dimmed state; `VoicePopover` renders `Section { rows } header: { caption }` inside one `LazyVStack`; the recommended section already models "a voice you could have but do not" with `isInstalled: false`, a size badge and an arrow.
- `Voice.regionName` derives `United States` and `United Kingdom` from the `en-US` and `en-GB` tags, so the catalogue needs no region strings of its own.
- `AppModel.pickVoice` is the one writer of `player.voice`; `AppModel.start()` is where launch work goes; `model.notice` is a plain sentence shown by `RootView`.
- `KokoroTTS.synthesize` chunks internally at about 15 seconds of speech, returns 24 kHz mono `[Float]`, honours cancellation between chunks, and maps an empty or unpronounceable input to `KokoroError.emptyText`, `.emptyPhonemizerOutput` or `.inaudibleChunk`. `prewarm` compiles the four models and runs one synthesis; the first call after an install takes tens of seconds, later ones about a second.
- A background `URLSession` on macOS continues a download while the app is not running, and an app that recreates the session with the same identifier reattaches to the task through `getAllTasks`. A dropped connection surfaces as an error whose `userInfo[NSURLSessionDownloadTaskResumeData]` resumes it.
- `AVAudioPlayerNode.scheduleBuffer(_:completionCallbackType: .dataPlayedBack)` calls back on an audio thread once the last sample has been rendered; `AVAudioEngineConfigurationChange` fires when the output device changes and the engine stops itself.

## Decisions taken here

- The model folders live under `Application Support/Aloud/Kokoro/` and `Caches/Aloud/Kokoro/`, one level under the `Aloud/` folder the progress file already uses, rather than the spec's `Application Support/Kokoro/`. The `make dev` build is not sandboxed, and an app should not claim a top-level folder in the reader's Library.
- Kokoro voices appear in the picker's Kokoro section only, not again in the English language section; the language sections are built from the provider's voices minus the Kokoro ids. Settings' plain picker lists them under English like any other voice once installed.
- Speed above 2x is passed straight to the model, as the spec's first choice. The by-ear check in Task 11 decides whether the time-pitch fallback is needed; it is not built ahead of the evidence.
- Strings for the section live in a `Copy` namespace in `Tokens.swift`, as the spec asks, even though the popover's existing captions are inline; the lint does not check strings, the spec does.

## File structure

`Speech`:

- Modify `Sources/Speech/VoiceProvider.swift`: the `prepare` requirement and its default.
- Modify `Sources/Speech/FakeVoiceProvider.swift`: records `prepared`, takes its voices in `init`.
- Modify `Sources/Speech/Player.swift`: calls `prepare` for the next sentence; `revalidateVoice()`.
- Create `Sources/Speech/CompositeVoiceProvider.swift`.
- Modify `Tests/SpeechTests/PlayerTests.swift`; create `Tests/SpeechTests/CompositeVoiceProviderTests.swift`.

`Kokoro`, a new module at `Sources/Kokoro`:

- `KokoroCatalogue.swift`: the seven voices, the prefix, region grouping.
- `KokoroRelease.swift`: the pinned download.
- `KokoroPaths.swift`: where files live.
- `KokoroStore.swift`: state, download, install, cancel, remove, launch cleanup; `KokoroDownloading` and `KokoroDownloadDelegate`.
- `URLSessionKokoroDownloader.swift`: the background session.
- `KokoroEngine.swift`: the actor over the SDK; `KokoroSynthesizing`; `KokoroEngineError`.
- `KokoroPlayback.swift`: the audio engine; `KokoroPlaying`.
- `KokoroVoiceProvider.swift`.
- Tests in `Tests/KokoroTests`: `KokoroCatalogueTests`, `KokoroStoreTests`, `KokoroVoiceProviderTests`, `KokoroIntegrationTests` (gated).

`AloudUI`:

- Modify `Sources/AloudUI/Components/VoiceRow.swift`: `isBusy`, `isDimmed`.
- Create `Sources/AloudUI/Components/DownloadBanner.swift`.
- Modify `Sources/AloudUI/Tokens.swift`: `Motion.opaque`, `Copy`.
- Modify `Sources/AloudUI/Gallery.swift`.

`Aloud`:

- Modify `Sources/Aloud/AloudApp.swift`, `AppModel.swift`, `VoicePopover.swift`, `SettingsView.swift`.
- Modify `Tests/AloudTests/AppModelTests.swift`.

Wiring and docs:

- Modify `Package.swift`, `project.yml`, `App/Aloud.entitlements`, `README.md`.

Working directory: `/Users/kevindazoo/aloud`, on a branch made for this plan.

---

### Task 1: `prepare` in the protocol, and the player asks for the next sentence

**Files:**
- Modify: `Sources/Speech/VoiceProvider.swift`
- Modify: `Sources/Speech/FakeVoiceProvider.swift`
- Modify: `Sources/Speech/Player.swift:180-217` (`speakCurrent`) and `:154-158` (`ensureVoiceIsInstalled`)
- Test: `Tests/SpeechTests/PlayerTests.swift`

**Interfaces:**
- Produces:

```swift
// VoiceProvider gains, with a default no-op in an extension:
@MainActor func prepare(_ text: String, voice: Voice?, rate: Rate)
// FakeVoiceProvider gains:
public struct Prepared: Sendable { let text: String; let voice: Voice?; let rate: Rate }
public private(set) var prepared: [Prepared]
public nonisolated init(voices: [Voice] = [Voice(id: "fake", name: "Fake", language: "en-US", quality: .standard)])
// Player gains:
public func revalidateVoice()
```

- [ ] **Step 1: Write the failing tests**

Append to the `PlayerTests` suite in `Tests/SpeechTests/PlayerTests.swift`, before its closing brace:

```swift
    /// While one sentence is spoken the next is handed to the provider to get ready, so
    /// an engine that synthesizes ahead can leave no gap at the boundary. The last
    /// sentence has nothing after it, and nothing is prepared.
    @Test func theNextSentenceIsPreparedWhileTheCurrentOneIsSpoken() {
        let (p, fake) = make()
        p.rate = .x15
        p.play()
        #expect(fake.prepared.map(\.text) == ["Four five six."])
        #expect(fake.prepared.last?.rate == .x15)
        fake.finishCurrent()
        #expect(fake.prepared.map(\.text) == ["Four five six.", "Seven eight nine."])
        fake.finishCurrent()
        fake.finishCurrent()
        #expect(p.sentenceIndex == 3)
        #expect(fake.prepared.map(\.text) == ["Four five six.", "Seven eight nine.", "Ten eleven twelve."])
    }

    /// A voice can stop being available without being reassigned, when its engine
    /// fails to load. The player is told to look again and falls back as it does for a
    /// voice removed in System Settings.
    @Test func revalidateFallsBackWhenTheVoiceHasGone() {
        let fake = FakeVoiceProvider(voices: [
            Voice(id: "fake", name: "Fake", language: "en-US", quality: .standard),
            Voice(id: "kokoro.af_bella", name: "Bella", language: "en-US", quality: .premium),
        ])
        let p = Player(provider: fake)
        p.voice = fake.voices[1]
        var unavailable: [Voice] = []
        p.onVoiceUnavailable = { unavailable.append($0) }
        fake.voices = [fake.voices[0]]
        p.revalidateVoice()
        #expect(p.voice?.id == "fake")
        #expect(unavailable.map(\.id) == ["kokoro.af_bella"])
    }
```

The second test needs `FakeVoiceProvider.voices` to be settable; the next step makes it so.

- [ ] **Step 2: Run to see them fail**

```bash
cd /Users/kevindazoo/aloud
make test 2>&1 | grep -E "error:" | head -3
```

Expected: `value of type 'FakeVoiceProvider' has no member 'prepared'` and no `init(voices:)`.

- [ ] **Step 3: Add the requirement and its default**

In `Sources/Speech/VoiceProvider.swift`, add to the protocol after `preview`:

```swift
    /// Tells the provider what will be asked for next, so an engine that synthesizes
    /// ahead can have it ready. Nothing is heard; a `speak` for the same text, voice
    /// and rate may then start without a gap. The system voice needs no warning and
    /// takes the default, which does nothing.
    @MainActor func prepare(_ text: String, voice: Voice?, rate: Rate)
```

and after the protocol:

```swift
extension VoiceProvider {
    @MainActor public func prepare(_ text: String, voice: Voice?, rate: Rate) {}
}
```

- [ ] **Step 4: Teach the fake to record it and to take its voices**

Replace the whole of `Sources/Speech/FakeVoiceProvider.swift` with:

```swift
import Foundation

/// Records what it was asked to speak and lets a test drive the callbacks.
/// Shipped in the module so the app can run silent with `--silent`.
@MainActor
public final class FakeVoiceProvider: VoiceProvider {
    public struct Request: Sendable {
        public let text: String
        public let rate: Rate
        public let voice: Voice?
        public let pause: Duration
        public let volume: Double
    }
    public struct Prepared: Sendable {
        public let text: String
        public let voice: Voice?
        public let rate: Rate
    }
    public private(set) var spoken: [Request] = []
    public private(set) var prepared: [Prepared] = []
    public private(set) var stops = 0
    public private(set) var previewed: [Voice] = []
    private var onWord: (@MainActor (NSRange) -> Void)?
    private var onFinish: (@MainActor () -> Void)?
    /// The set is a lock-guarded value rather than a main-actor property because the
    /// protocol reads it nonisolated; a test changes it to take a voice away.
    private let installed: Installed

    public nonisolated init(
        voices: [Voice] = [Voice(id: "fake", name: "Fake", language: "en-US", quality: .standard)]
    ) {
        installed = Installed(voices)
    }
    public nonisolated var voices: [Voice] {
        get { installed.get() }
        set { installed.set(newValue) }
    }
    public nonisolated var defaultVoice: Voice? { voices.first }
    /// Nothing is cached, so there is nothing to forget.
    public nonisolated func refreshVoices() {}
    public func speak(
        _ text: String, voice: Voice?, rate: Rate, pause: Duration, volume: Double,
        onWord: @escaping @MainActor (NSRange) -> Void, onFinish: @escaping @MainActor () -> Void
    ) {
        spoken.append(Request(text: text, rate: rate, voice: voice, pause: pause, volume: volume))
        self.onWord = onWord
        self.onFinish = onFinish
    }
    public func prepare(_ text: String, voice: Voice?, rate: Rate) {
        prepared.append(Prepared(text: text, voice: voice, rate: rate))
    }
    public func preview(_ voice: Voice) { previewed.append(voice) }
    public func stop() {
        stops += 1
        onWord = nil
        onFinish = nil
    }
    public func finishCurrent() {
        let f = onFinish
        onFinish = nil
        onWord = nil
        f?()
    }
    public func word(_ range: NSRange) { onWord?(range) }
}

private final class Installed: @unchecked Sendable {
    private let lock = NSLock()
    private var voices: [Voice]
    init(_ voices: [Voice]) { self.voices = voices }
    func get() -> [Voice] { lock.withLock { voices } }
    func set(_ new: [Voice]) { lock.withLock { voices = new } }
}
```

- [ ] **Step 5: Make the player prepare the next sentence and expose the check**

In `Sources/Speech/Player.swift`, inside `speakCurrent`, after the `provider.speak(...)` call's closing parenthesis, add:

```swift
        // The sentence after this one is handed over now, so an engine that renders
        // ahead has it by the time the boundary comes. The last has nothing after it.
        if sentenceIndex + 1 < script.sentences.count {
            provider.prepare(script.sentences[sentenceIndex + 1].text, voice: voice, rate: rate)
        }
```

Add a public method next to `ensureVoiceIsInstalled`:

```swift
    /// Asks again whether the chosen voice is still there. Assignment and `play` ask on
    /// their own; this is for the moment a voice goes away without either, when its
    /// engine fails to load.
    public func revalidateVoice() { ensureVoiceIsInstalled() }
```

- [ ] **Step 6: Run the tests**

```bash
make test 2>&1 | grep -E "Test .* (passed|failed)|error:" | grep -E "Prepared|revalidate|error" | head -5
make test 2>&1 | grep -E "Test run" | tail -1
```

Expected: both new tests pass and the whole suite is green. The existing `PlayerTests` still pass: `prepare` on the fake only records.

- [ ] **Step 7: Check and commit**

```bash
make check 2>&1 | tail -3
git add Sources/Speech/VoiceProvider.swift Sources/Speech/FakeVoiceProvider.swift Sources/Speech/Player.swift Tests/SpeechTests/PlayerTests.swift
git commit -m "The player hands the provider the next sentence while the current one is spoken"
```

---

### Task 2: The composite provider

**Files:**
- Create: `Sources/Speech/CompositeVoiceProvider.swift`
- Test: `Tests/SpeechTests/CompositeVoiceProviderTests.swift`

**Interfaces:**
- Produces:

```swift
@MainActor public final class CompositeVoiceProvider: VoiceProvider {
  public nonisolated init(primary: any VoiceProvider, secondary: any VoiceProvider, secondaryPrefix: String)
  // voices: secondary's first, then primary's; defaultVoice: primary's; refreshVoices: both
  // speak, prepare, preview: routed by whether voice.id has secondaryPrefix; stop: both
}
```

- [ ] **Step 1: Write the failing tests**

Create `Tests/SpeechTests/CompositeVoiceProviderTests.swift`:

```swift
import Foundation
import Testing

@testable import Speech

@Suite @MainActor struct CompositeVoiceProviderTests {
    let apple = Voice(id: "com.apple.voice.samantha", name: "Samantha", language: "en-US", quality: .premium)
    let bella = Voice(id: "kokoro.af_bella", name: "Bella", language: "en-US", quality: .premium)

    func make() -> (CompositeVoiceProvider, FakeVoiceProvider, FakeVoiceProvider) {
        let a = FakeVoiceProvider(voices: [apple])
        let k = FakeVoiceProvider(voices: [bella])
        return (CompositeVoiceProvider(primary: a, secondary: k, secondaryPrefix: "kokoro."), a, k)
    }

    /// The list is one list, the second engine's voices first so a section can be cut
    /// off the top of it; the default voice is the system's.
    @Test func voicesAreConcatenatedSecondaryFirst() {
        let (c, _, _) = make()
        #expect(c.voices.map(\.id) == ["kokoro.af_bella", "com.apple.voice.samantha"])
        #expect(c.defaultVoice?.id == "com.apple.voice.samantha")
    }

    @Test func speakAndPrepareGoToTheProviderThePrefixNames() {
        let (c, a, k) = make()
        c.speak("One.", voice: bella, rate: .x1, pause: .zero, volume: 1, onWord: { _ in }, onFinish: {})
        c.prepare("Two.", voice: bella, rate: .x1)
        #expect(k.spoken.map(\.text) == ["One."])
        #expect(k.prepared.map(\.text) == ["Two."])
        #expect(a.spoken.isEmpty && a.prepared.isEmpty)
        c.speak("Three.", voice: apple, rate: .x1, pause: .zero, volume: 1, onWord: { _ in }, onFinish: {})
        c.prepare("Four.", voice: nil, rate: .x1)
        #expect(a.spoken.map(\.text) == ["Three."])
        #expect(a.prepared.map(\.text) == ["Four."])
        #expect(k.spoken.count == 1)
    }

    /// A finish from the routed provider reaches the caller unchanged.
    @Test func callbacksPassThrough() {
        let (c, _, k) = make()
        var finished = 0
        c.speak("One.", voice: bella, rate: .x1, pause: .zero, volume: 1, onWord: { _ in }, onFinish: { finished += 1 })
        k.finishCurrent()
        #expect(finished == 1)
    }

    @Test func previewIsRoutedByTheVoice() {
        let (c, a, k) = make()
        c.preview(bella)
        c.preview(apple)
        #expect(k.previewed.map(\.id) == ["kokoro.af_bella"])
        #expect(a.previewed.map(\.id) == ["com.apple.voice.samantha"])
    }

    /// A preview from one engine may be interrupting speech from the other, so a stop
    /// reaches both.
    @Test func stopReachesBoth() {
        let (c, a, k) = make()
        c.stop()
        #expect(a.stops == 1 && k.stops == 1)
    }

    @Test func refreshReachesBothAndAChangeInEitherShows() {
        let (c, a, k) = make()
        c.refreshVoices()
        k.voices = []
        #expect(c.voices.map(\.id) == ["com.apple.voice.samantha"])
        a.voices = []
        #expect(c.voices.isEmpty)
    }
}
```

- [ ] **Step 2: Run to see them fail**

```bash
make test 2>&1 | grep -E "error:" | head -3
```

Expected: `cannot find 'CompositeVoiceProvider' in scope`.

- [ ] **Step 3: Implement it**

Create `Sources/Speech/CompositeVoiceProvider.swift`:

```swift
import Foundation

/// Two engines behind one provider, so the player and the picker keep one. The second
/// engine owns the ids under its prefix; everything else is the first's. The list is
/// the second's voices and then the first's, which lets a picker cut a section off the
/// top; the default voice is the first's, the system's.
@MainActor
public final class CompositeVoiceProvider: VoiceProvider {
    private let primary: any VoiceProvider
    private let secondary: any VoiceProvider
    private let secondaryPrefix: String

    public nonisolated init(primary: any VoiceProvider, secondary: any VoiceProvider, secondaryPrefix: String) {
        self.primary = primary
        self.secondary = secondary
        self.secondaryPrefix = secondaryPrefix
    }

    public nonisolated var voices: [Voice] { secondary.voices + primary.voices }
    public nonisolated var defaultVoice: Voice? { primary.defaultVoice }
    public nonisolated func refreshVoices() {
        primary.refreshVoices()
        secondary.refreshVoices()
    }

    private func provider(for voice: Voice?) -> any VoiceProvider {
        voice?.id.hasPrefix(secondaryPrefix) == true ? secondary : primary
    }

    public func speak(
        _ text: String, voice: Voice?, rate: Rate, pause: Duration, volume: Double,
        onWord: @escaping @MainActor (NSRange) -> Void, onFinish: @escaping @MainActor () -> Void
    ) {
        provider(for: voice).speak(
            text, voice: voice, rate: rate, pause: pause, volume: volume, onWord: onWord, onFinish: onFinish)
    }

    public func prepare(_ text: String, voice: Voice?, rate: Rate) {
        provider(for: voice).prepare(text, voice: voice, rate: rate)
    }

    public func preview(_ voice: Voice) { provider(for: voice).preview(voice) }

    /// A preview from one engine may be what interrupts speech from the other, so both
    /// are told.
    public func stop() {
        primary.stop()
        secondary.stop()
    }
}
```

- [ ] **Step 4: Run the tests**

```bash
make test 2>&1 | grep -E "CompositeVoiceProviderTests|Test run" | tail -3
```

Expected: six passes and a green run.

- [ ] **Step 5: Check and commit**

```bash
make check 2>&1 | tail -3
git add Sources/Speech/CompositeVoiceProvider.swift Tests/SpeechTests/CompositeVoiceProviderTests.swift
git commit -m "One provider over two engines, routed by the voice id's prefix"
```

---

### Task 3: The `Kokoro` module, its catalogue, the pinned release, and where files live

**Files:**
- Modify: `Package.swift`
- Modify: `project.yml`
- Modify: `App/Aloud.entitlements`
- Create: `Sources/Kokoro/KokoroCatalogue.swift`
- Create: `Sources/Kokoro/KokoroRelease.swift`
- Create: `Sources/Kokoro/KokoroPaths.swift`
- Test: `Tests/KokoroTests/KokoroCatalogueTests.swift`

**Interfaces:**
- Produces:

```swift
public struct KokoroVoice: Sendable, Hashable, Identifiable {
  let kokoroID: String; let name: String; let language: String
  var id: String            // "kokoro." + kokoroID
  var voice: Voice          // Speech.Voice, quality .premium
  var british: Bool         // kokoroID starts with "b"
}
public struct KokoroRegion: Identifiable, Sendable { let name: String; let voices: [KokoroVoice]; var id: String { name } }
public enum KokoroCatalogue {
  static let prefix = "kokoro."
  static let voices: [KokoroVoice]                 // the seven, in the order above
  static var speechVoices: [Voice]
  static func isKokoro(_ id: String) -> Bool
  static func voice(for id: String) -> KokoroVoice?   // by Aloud id
  static var regions: [KokoroRegion]               // United States, then United Kingdom
}
public struct KokoroReleaseInfo: Sendable, Equatable { let url: URL; let version: String; let sha256: String; let bytes: Int64; var sizeLabel: String }
public enum KokoroRelease { static let current: KokoroReleaseInfo }
public struct KokoroPaths: Sendable {
  init(support: URL, caches: URL); static func standard() -> KokoroPaths
  func modelDirectory(version: String) -> URL      // support/<version>
  func marker(version: String) -> URL              // support/<version>/.complete
  func compiledCache(version: String) -> URL       // caches/<version>
  var resumeData: URL                              // support/resume.data
  var archive: URL                                 // support/download.aar
  var installing: URL                              // support/.installing
}
```

- [ ] **Step 1: Wire the module**

In `Package.swift`, add to `products` after the `KokoroBundle` product:

```swift
        .library(name: "Kokoro", targets: ["Kokoro"]),
```

Add to `targets` after the `Speech` target:

```swift
        // The second engine, beside Speech: the catalogue, the model store, the SDK
        // actor, the audio player and the provider. Speech never imports it.
        .target(
            name: "Kokoro",
            dependencies: ["Speech", "KokoroBundle", .product(name: "KokoroTTS", package: "kokoro-coreml")],
            swiftSettings: strict),
```

Add `"Kokoro"` to the `Aloud` executable target's dependencies, after `"Speech"`.

Add to `targets` after the `SpeechTests` entry:

```swift
        .testTarget(name: "KokoroTests", dependencies: ["Kokoro", "Speech", "KokoroBundle"], swiftSettings: strict),
```

In `project.yml`, under the `Aloud` target's `dependencies`, after the `Speech` product entry:

```yaml
      - package: Aloud
        product: Kokoro
      - package: Aloud
        product: KokoroBundle
```

and in the `entitlements.properties` block:

```yaml
        com.apple.security.network.client: true
```

In `App/Aloud.entitlements`, add inside the `dict`:

```xml
    <key>com.apple.security.network.client</key><true/>
```

- [ ] **Step 2: Write the failing tests**

Create `Tests/KokoroTests/KokoroCatalogueTests.swift`:

```swift
import Foundation
import Speech
import Testing

@testable import Kokoro

@Suite struct KokoroCatalogueTests {
    /// The seven voices, in the spec's order, each under the prefix so no id can meet
    /// an Apple identifier.
    @Test func theSevenVoicesInOrder() {
        #expect(
            KokoroCatalogue.voices.map(\.id) == [
                "kokoro.af_bella", "kokoro.af_sarah", "kokoro.am_michael", "kokoro.am_fenrir",
                "kokoro.bf_emma", "kokoro.bm_george", "kokoro.bm_fable",
            ])
        #expect(
            KokoroCatalogue.voices.map(\.name) == ["Bella", "Sarah", "Michael", "Fenrir", "Emma", "George", "Fable"])
        #expect(KokoroCatalogue.voices.prefix(4).allSatisfy { $0.language == "en-US" && !$0.british })
        #expect(KokoroCatalogue.voices.suffix(3).allSatisfy { $0.language == "en-GB" && $0.british })
        #expect(KokoroCatalogue.speechVoices.allSatisfy { $0.quality == .premium })
    }

    @Test func idsRoundTrip() {
        #expect(KokoroCatalogue.isKokoro("kokoro.af_bella"))
        #expect(!KokoroCatalogue.isKokoro("com.apple.voice.premium.en-US.Zoe"))
        #expect(KokoroCatalogue.voice(for: "kokoro.bm_fable")?.kokoroID == "bm_fable")
        #expect(KokoroCatalogue.voice(for: "kokoro.zz_nobody") == nil)
        #expect(KokoroCatalogue.voice(for: "af_bella") == nil)
    }

    /// Grouped by region for the picker: American first, as the catalogue lists them.
    @Test func regionsFollowTheCatalogue() {
        let regions = KokoroCatalogue.regions
        #expect(regions.map(\.name) == ["United States", "United Kingdom"])
        #expect(regions[0].voices.map(\.name) == ["Bella", "Sarah", "Michael", "Fenrir"])
        #expect(regions[1].voices.map(\.name) == ["Emma", "George", "Fable"])
    }

    @Test func theReleaseIsPinned() {
        let r = KokoroRelease.current
        #expect(r.url.absoluteString == "https://github.com/kevxuUmich/Aloud/releases/download/kokoro-models/kokoro-1.aar")
        #expect(r.version == "1")
        #expect(r.sha256.count == 64 && r.sha256 == r.sha256.lowercased())
        #expect(r.bytes > 100_000_000)
        #expect(r.sizeLabel.hasSuffix(" MB"))
    }

    @Test func pathsHangOffTheTwoRoots() {
        let p = KokoroPaths(support: URL(fileURLWithPath: "/s"), caches: URL(fileURLWithPath: "/c"))
        #expect(p.modelDirectory(version: "1").path == "/s/1")
        #expect(p.marker(version: "1").path == "/s/1/.complete")
        #expect(p.compiledCache(version: "1").path == "/c/1")
        #expect(p.resumeData.path == "/s/resume.data")
        #expect(p.archive.path == "/s/download.aar")
        #expect(p.installing.path == "/s/.installing")
        let standard = KokoroPaths.standard()
        #expect(standard.support.path.hasSuffix("/Application Support/Aloud/Kokoro"))
        #expect(standard.caches.path.hasSuffix("/Caches/Aloud/Kokoro"))
    }
}
```

- [ ] **Step 3: Run to see them fail**

```bash
swift build --target KokoroTests 2>&1 | grep -E "error:" | head -3
```

Expected: the module has no sources yet, or `KokoroCatalogue` is not found.

- [ ] **Step 4: Write the catalogue**

Create `Sources/Kokoro/KokoroCatalogue.swift`:

```swift
import Foundation
import Speech

/// One of the shipped Kokoro voices: the id the engine knows it by, the name the
/// picker shows, and the language tag the region and the phonemizer come from.
public struct KokoroVoice: Sendable, Hashable, Identifiable {
    public let kokoroID: String
    public let name: String
    public let language: String

    /// The Aloud id: the engine's id under the prefix, so it never meets an Apple
    /// identifier.
    public var id: String { KokoroCatalogue.prefix + kokoroID }
    /// The voice as the rest of the app sees it. Premium, so it sorts to the top of a
    /// language section.
    public var voice: Voice { Voice(id: id, name: name, language: language, quality: .premium) }
    /// British voices take the British phonemizer; the engine reads it off the id too.
    public var british: Bool { kokoroID.hasPrefix("b") }
}

/// The picker's grouping: one region, its voices in catalogue order.
public struct KokoroRegion: Identifiable, Sendable {
    public let name: String
    public let voices: [KokoroVoice]
    public var id: String { name }
}

public enum KokoroCatalogue {
    public static let prefix = "kokoro."

    /// The seven, American then British, as the spec lists them.
    public static let voices: [KokoroVoice] = [
        KokoroVoice(kokoroID: "af_bella", name: "Bella", language: "en-US"),
        KokoroVoice(kokoroID: "af_sarah", name: "Sarah", language: "en-US"),
        KokoroVoice(kokoroID: "am_michael", name: "Michael", language: "en-US"),
        KokoroVoice(kokoroID: "am_fenrir", name: "Fenrir", language: "en-US"),
        KokoroVoice(kokoroID: "bf_emma", name: "Emma", language: "en-GB"),
        KokoroVoice(kokoroID: "bm_george", name: "George", language: "en-GB"),
        KokoroVoice(kokoroID: "bm_fable", name: "Fable", language: "en-GB"),
    ]

    public static var speechVoices: [Voice] { voices.map(\.voice) }

    public static func isKokoro(_ id: String) -> Bool { id.hasPrefix(prefix) }

    public static func voice(for id: String) -> KokoroVoice? { voices.first { $0.id == id } }

    /// Grouped by region name, in the order the regions first appear.
    public static var regions: [KokoroRegion] {
        var names: [String] = []
        var grouped: [String: [KokoroVoice]] = [:]
        for v in voices {
            let name = v.voice.regionName ?? v.language
            if grouped[name] == nil { names.append(name) }
            grouped[name, default: []].append(v)
        }
        return names.map { KokoroRegion(name: $0, voices: grouped[$0] ?? []) }
    }
}
```

- [ ] **Step 5: Write the pinned release and the paths**

Create `Sources/Kokoro/KokoroRelease.swift`, substituting the SHA-256 and byte count plan 2 printed:

```swift
import Foundation

/// Everything the download is pinned by. Bumping the bundle is a change to these values
/// and a new release asset; nothing else in the app knows a version.
public struct KokoroReleaseInfo: Sendable, Equatable {
    public let url: URL
    public let version: String
    public let sha256: String
    public let bytes: Int64
    public init(url: URL, version: String, sha256: String, bytes: Int64) {
        self.url = url
        self.version = version
        self.sha256 = sha256
        self.bytes = bytes
    }
    /// The size as the picker's badge shows it, in whole megabytes.
    public var sizeLabel: String { "\(bytes / 1_000_000) MB" }
}

public enum KokoroRelease {
    public static let current = KokoroReleaseInfo(
        url: URL(string: "https://github.com/kevxuUmich/Aloud/releases/download/kokoro-models/kokoro-1.aar")!,
        version: "1",
        sha256: "c70f436d665855f507f2fe828097b24baf30a508ba2ea5cb45f6da0dac7d6ca5",
        bytes: 159_237_319)
}
```

The two values are the ones plan 2 published (its Task 5 printed them as `sha256:` and `bytes:`); they are also `curl -sL https://github.com/kevxuUmich/Aloud/releases/download/kokoro-models/kokoro-1.aar.sha256` and `gh release view kokoro-models --json assets -q '.assets[] | select(.name=="kokoro-1.aar") | .size'`.
They are already filled in above; the test refuses a placeholder.
The values above are the ones this plan pinned; the final fix wave replaced them with `kokoro-2.aar`'s, and the file itself is the record of what the app pins today.

Create `Sources/Kokoro/KokoroPaths.swift`:

```swift
import Foundation

/// Where the model lives. Both roots are the app's own folders, under the `Aloud`
/// folder the progress file already uses, so no file entitlement changes; in the
/// sandboxed build they resolve inside the container.
public struct KokoroPaths: Sendable {
    public let support: URL
    public let caches: URL

    public init(support: URL, caches: URL) {
        self.support = support
        self.caches = caches
    }

    public static func standard() -> KokoroPaths {
        let fm = FileManager.default
        let support = fm.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("Aloud/Kokoro", isDirectory: true)
        let caches = fm.urls(for: .cachesDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("Aloud/Kokoro", isDirectory: true)
        return KokoroPaths(support: support, caches: caches)
    }

    /// The installed bundle: the SDK's manifest at its root.
    public func modelDirectory(version: String) -> URL {
        support.appendingPathComponent(version, isDirectory: true)
    }
    /// Written last, so a folder without it is a crash mid-install to be swept away.
    public func marker(version: String) -> URL {
        modelDirectory(version: version).appendingPathComponent(".complete")
    }
    /// The compiled CoreML models, excluded from backup; removed with the version.
    public func compiledCache(version: String) -> URL {
        caches.appendingPathComponent(version, isDirectory: true)
    }
    /// What a dropped connection leaves behind for the next attempt to continue from.
    public var resumeData: URL { support.appendingPathComponent("resume.data") }
    /// Where a finished download waits for its checksum.
    public var archive: URL { support.appendingPathComponent("download.aar") }
    /// Where an archive is extracted before it is moved into place whole.
    public var installing: URL { support.appendingPathComponent(".installing", isDirectory: true) }
}
```

- [ ] **Step 6: Run the tests**

```bash
make test 2>&1 | grep -E "KokoroCatalogueTests|Test run" | tail -3
```

Expected: five passes.

- [ ] **Step 7: Check and commit**

```bash
make check 2>&1 | tail -3
git add Package.swift Package.resolved project.yml App/Aloud.entitlements Sources/Kokoro Tests/KokoroTests
git commit -m "A Kokoro module with the seven voices, the pinned download and its folders"
```

---

### Task 4: The store: install, marker, remove, cancel, and the launch sweep

**Files:**
- Create: `Sources/Kokoro/KokoroStore.swift`
- Test: `Tests/KokoroTests/KokoroStoreTests.swift`

**Interfaces:**
- Consumes: `KokoroPaths`, `KokoroReleaseInfo`, `AppleArchiveFile.extract` from `KokoroBundle`.
- Produces:

```swift
public enum KokoroStoreState: Sendable, Equatable {
  case absent, downloading(Double), installing, installed(version: String, bytes: Int64), failed(String)
}
public enum KokoroDownloadFailure: Error, Sendable, Equatable { case offline, http(Int), other(String) }
@MainActor public protocol KokoroDownloadDelegate: AnyObject {
  func downloadProgressed(_ fraction: Double)
  func downloadFinished()                                   // the file is at the destination
  func downloadFailed(_ failure: KokoroDownloadFailure, resumeData: Data?)
}
public protocol KokoroDownloading: AnyObject, Sendable {
  @MainActor func download(_ url: URL, to destination: URL, resumeData: Data?, delegate: any KokoroDownloadDelegate)
  @MainActor func reattach(to destination: URL, delegate: any KokoroDownloadDelegate) async -> Bool
  @MainActor func cancel()
}
@Observable @MainActor public final class KokoroStore {
  public private(set) var state: KokoroStoreState
  public var onInstalled: (@MainActor () -> Void)?
  public nonisolated var isInstalledNow: Bool     // lock-guarded snapshot for nonisolated readers
  public init(paths: KokoroPaths, release: KokoroReleaseInfo, downloader: any KokoroDownloading,
              extract: @escaping @Sendable (URL, URL) throws -> Void = AppleArchiveFile.extract)
  public var installedRoot: URL?
  public var compiledCache: URL
  public func start() async
  public func download()
  public func cancel()
  public func remove()
  var installTask: Task<Void, Never>?           // internal, so tests can await an install
}
```

The store runs the checksum and extraction off the main actor in a detached task; everything else is main-actor state.

- [ ] **Step 1: Write the failing tests**

Create `Tests/KokoroTests/KokoroStoreTests.swift`:

```swift
import CryptoKit
import Foundation
import KokoroBundle
import Testing

@testable import Kokoro

/// A downloader a test drives by hand: it records what it was asked and delivers
/// progress, a finished file or a failure when told to.
@MainActor final class FakeDownloader: KokoroDownloading {
    struct Request { let url: URL; let destination: URL; let resumeData: Data? }
    var requests: [Request] = []
    var cancels = 0
    var running = false
    weak var delegate: (any KokoroDownloadDelegate)?
    var destination: URL?

    nonisolated init() {}
    func download(_ url: URL, to destination: URL, resumeData: Data?, delegate: any KokoroDownloadDelegate) {
        requests.append(Request(url: url, destination: destination, resumeData: resumeData))
        self.delegate = delegate
        self.destination = destination
    }
    func reattach(to destination: URL, delegate: any KokoroDownloadDelegate) async -> Bool {
        guard running else { return false }
        self.delegate = delegate
        self.destination = destination
        return true
    }
    func cancel() { cancels += 1 }

    func progress(_ f: Double) { delegate?.downloadProgressed(f) }
    func finish(with data: Data) throws {
        try data.write(to: destination!)
        delegate?.downloadFinished()
    }
    func fail(_ failure: KokoroDownloadFailure, resumeData: Data? = nil) {
        delegate?.downloadFailed(failure, resumeData: resumeData)
    }
}

@Suite @MainActor struct KokoroStoreTests {
    func scratch() throws -> URL {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        return url
    }

    /// A real, tiny archive of a bundle-shaped tree, and the release that pins it.
    func makeArchive() throws -> (data: Data, release: KokoroReleaseInfo) {
        let tree = try scratch()
        try FileManager.default.createDirectory(at: tree.appendingPathComponent("voices"), withIntermediateDirectories: true)
        try Data("{\"schema_version\": 1}\n".utf8).write(to: tree.appendingPathComponent("KokoroRuntimeManifest.json"))
        try Data(count: 1024).write(to: tree.appendingPathComponent("voices/af_bella.bin"))
        let archive = try scratch().appendingPathComponent("kokoro-1.aar")
        try AppleArchiveFile.compress(directory: tree, to: archive)
        let data = try Data(contentsOf: archive)
        let sha = SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined()
        let release = KokoroReleaseInfo(
            url: URL(string: "https://example.invalid/kokoro-1.aar")!, version: "1", sha256: sha, bytes: Int64(data.count))
        return (data, release)
    }

    func make(release: KokoroReleaseInfo) throws -> (KokoroStore, FakeDownloader, KokoroPaths) {
        let root = try scratch()
        let paths = KokoroPaths(
            support: root.appendingPathComponent("support"), caches: root.appendingPathComponent("caches"))
        let downloader = FakeDownloader()
        let store = KokoroStore(paths: paths, release: release, downloader: downloader)
        return (store, downloader, paths)
    }

    func install(_ store: KokoroStore) async {
        await store.installTask?.value
    }

    @Test func aFreshStoreIsAbsent() async throws {
        let (store, _, _) = try make(release: try makeArchive().release)
        await store.start()
        #expect(store.state == .absent)
        #expect(!store.isInstalledNow)
        #expect(store.installedRoot == nil)
    }

    /// The whole happy path: download reports progress, the file matches, it is
    /// extracted into place, the marker is written last, and the store says installed.
    @Test func aMatchingDownloadIsInstalled() async throws {
        let (data, release) = try makeArchive()
        let (store, downloader, paths) = try make(release: release)
        await store.start()
        var installed = 0
        store.onInstalled = { installed += 1 }

        store.download()
        #expect(downloader.requests.map(\.url) == [release.url])
        #expect(downloader.requests.first?.destination == paths.archive)
        #expect(store.state == .downloading(0))
        downloader.progress(0.4)
        #expect(store.state == .downloading(0.4))
        try downloader.finish(with: data)
        #expect(store.state == .installing)
        await install(store)

        guard case .installed(let version, let bytes) = store.state else {
            Issue.record("expected installed, got \(store.state)")
            return
        }
        #expect(version == "1")
        #expect(bytes == 1024 + 21)
        #expect(store.isInstalledNow)
        #expect(installed == 1)
        #expect(store.installedRoot == paths.modelDirectory(version: "1"))
        #expect(FileManager.default.fileExists(atPath: paths.marker(version: "1").path))
        #expect(FileManager.default.fileExists(atPath: paths.modelDirectory(version: "1").appendingPathComponent("voices/af_bella.bin").path))
        #expect(!FileManager.default.fileExists(atPath: paths.archive.path))
        #expect(!FileManager.default.fileExists(atPath: paths.installing.path))
        #expect(FileManager.default.fileExists(atPath: paths.compiledCache(version: "1").path))
    }

    /// A file that does not hash to the pinned value is deleted and reported; nothing
    /// is extracted.
    @Test func aMismatchedDownloadIsDeletedAndFails() async throws {
        let (data, release) = try makeArchive()
        let (store, downloader, paths) = try make(release: release)
        await store.start()
        store.download()
        var wrong = data
        wrong[wrong.count - 1] ^= 0xFF
        try downloader.finish(with: wrong)
        await install(store)
        #expect(store.state == .failed("The download did not match what Aloud expected."))
        #expect(!FileManager.default.fileExists(atPath: paths.archive.path))
        #expect(!FileManager.default.fileExists(atPath: paths.modelDirectory(version: "1").path))
        #expect(!store.isInstalledNow)
    }

    @Test func downloadFailuresAreSaidInOneSentence() async throws {
        let (store, downloader, _) = try make(release: try makeArchive().release)
        await store.start()
        store.download()
        downloader.fail(.offline)
        #expect(store.state == .failed("No internet connection."))
        store.download()
        downloader.fail(.http(404))
        #expect(store.state == .failed("The server answered 404."))
        store.download()
        downloader.fail(.other("boom"))
        #expect(store.state == .failed("boom"))
    }

    /// A dropped connection leaves resume data, and the retry hands it back to the
    /// downloader so the bytes already fetched are not fetched again.
    @Test func retryResumesFromResumeData() async throws {
        let (store, downloader, paths) = try make(release: try makeArchive().release)
        await store.start()
        store.download()
        downloader.fail(.offline, resumeData: Data("partial".utf8))
        #expect(try Data(contentsOf: paths.resumeData) == Data("partial".utf8))
        store.download()
        #expect(downloader.requests.last?.resumeData == Data("partial".utf8))
    }

    /// Cancel is the reader's, not a failure: the task is cancelled, the resume data
    /// dropped, and the store is back where it started.
    @Test func cancelReturnsToAbsent() async throws {
        let (store, downloader, paths) = try make(release: try makeArchive().release)
        await store.start()
        store.download()
        downloader.progress(0.5)
        store.cancel()
        #expect(downloader.cancels == 1)
        #expect(store.state == .absent)
        #expect(!FileManager.default.fileExists(atPath: paths.resumeData.path))
        // A late callback from the cancelled task changes nothing.
        downloader.progress(0.9)
        #expect(store.state == .absent)
    }

    @Test func removeDeletesTheVersionAndItsCache() async throws {
        let (data, release) = try makeArchive()
        let (store, downloader, paths) = try make(release: release)
        await store.start()
        store.download()
        try downloader.finish(with: data)
        await install(store)
        store.remove()
        #expect(store.state == .absent)
        #expect(!store.isInstalledNow)
        #expect(!FileManager.default.fileExists(atPath: paths.modelDirectory(version: "1").path))
        #expect(!FileManager.default.fileExists(atPath: paths.compiledCache(version: "1").path))
    }

    /// The next launch finds what the last one installed.
    @Test func startFindsAnInstalledVersion() async throws {
        let (data, release) = try makeArchive()
        let (store, downloader, paths) = try make(release: release)
        await store.start()
        store.download()
        try downloader.finish(with: data)
        await install(store)
        let again = KokoroStore(paths: paths, release: release, downloader: FakeDownloader())
        await again.start()
        #expect(again.state == .installed(version: "1", bytes: 1024 + 21))
        #expect(again.isInstalledNow)
    }

    /// A folder without the marker is a crash mid-install; an older version folder is
    /// last release's; a leftover extraction folder is either. All three are swept.
    @Test func startSweepsWhatShouldNotBeThere() async throws {
        let (data, release) = try makeArchive()
        let (store, downloader, paths) = try make(release: release)
        await store.start()
        store.download()
        try downloader.finish(with: data)
        await install(store)
        let fm = FileManager.default
        try fm.createDirectory(at: paths.modelDirectory(version: "0"), withIntermediateDirectories: true)
        try fm.createDirectory(at: paths.compiledCache(version: "0"), withIntermediateDirectories: true)
        try fm.createDirectory(at: paths.installing, withIntermediateDirectories: true)
        let unmarked = paths.modelDirectory(version: "1")
        try fm.removeItem(at: paths.marker(version: "1"))

        let again = KokoroStore(paths: paths, release: release, downloader: FakeDownloader())
        await again.start()

        #expect(again.state == .absent)
        #expect(!fm.fileExists(atPath: unmarked.path))
        #expect(!fm.fileExists(atPath: paths.modelDirectory(version: "0").path))
        #expect(!fm.fileExists(atPath: paths.compiledCache(version: "0").path))
        #expect(!fm.fileExists(atPath: paths.installing.path))
    }

    /// A download the last launch left running is picked up, not restarted.
    @Test func startReattachesToARunningDownload() async throws {
        let (store, _, paths) = try make(release: try makeArchive().release)
        _ = store
        let downloader = FakeDownloader()
        downloader.running = true
        let again = KokoroStore(paths: paths, release: try makeArchive().release, downloader: downloader)
        await again.start()
        #expect(again.state == .downloading(0))
        #expect(downloader.requests.isEmpty)
        downloader.progress(0.7)
        #expect(again.state == .downloading(0.7))
    }

    /// Resume data from an app that quit mid-download is resumed at the next launch.
    @Test func startResumesFromResumeData() async throws {
        let (store, downloader, paths) = try make(release: try makeArchive().release)
        await store.start()
        store.download()
        downloader.fail(.offline, resumeData: Data("partial".utf8))
        let fresh = FakeDownloader()
        let again = KokoroStore(paths: paths, release: try makeArchive().release, downloader: fresh)
        await again.start()
        #expect(again.state == .downloading(0))
        #expect(fresh.requests.last?.resumeData == Data("partial".utf8))
    }
}
```

`bytes == 1024 + 21` is the tree's file bytes: the voice row and the 21-byte manifest.

- [ ] **Step 2: Run to see them fail**

```bash
make test 2>&1 | grep -E "error:" | head -3
```

Expected: `cannot find type 'KokoroDownloading' in scope`.

- [ ] **Step 3: Implement the store**

Create `Sources/Kokoro/KokoroStore.swift`:

```swift
import CryptoKit
import Foundation
import KokoroBundle
import Synchronization

public enum KokoroStoreState: Sendable, Equatable {
    case absent
    case downloading(Double)
    case installing
    case installed(version: String, bytes: Int64)
    case failed(String)
}

public enum KokoroDownloadFailure: Error, Sendable, Equatable {
    case offline
    case http(Int)
    case other(String)
}

/// What a downloader tells the store, on the main actor.
@MainActor
public protocol KokoroDownloadDelegate: AnyObject {
    func downloadProgressed(_ fraction: Double)
    /// The file is at the destination the download was asked for.
    func downloadFinished()
    func downloadFailed(_ failure: KokoroDownloadFailure, resumeData: Data?)
}

/// Downloads one file. The background session is the real one; tests drive a fake.
public protocol KokoroDownloading: AnyObject, Sendable {
    @MainActor func download(_ url: URL, to destination: URL, resumeData: Data?, delegate: any KokoroDownloadDelegate)
    /// Picks up a download a previous launch left running. True when there is one.
    @MainActor func reattach(to destination: URL, delegate: any KokoroDownloadDelegate) async -> Bool
    @MainActor func cancel()
}

/// The model's life on disk: absent, arriving, being checked and unpacked, installed,
/// or failed with a sentence. The one writer of the model folders.
@Observable @MainActor
public final class KokoroStore {
    public static let mismatchMessage = "The download did not match what Aloud expected."
    public static let offlineMessage = "No internet connection."
    public static let diskFullMessage = "Not enough disk space."

    public private(set) var state: KokoroStoreState = .absent {
        didSet {
            installedFlag.withLock { $0 = isInstalled }
        }
    }
    /// Called once an install completes, so a pick made before the download can take.
    public var onInstalled: (@MainActor () -> Void)?

    public let paths: KokoroPaths
    public let release: KokoroReleaseInfo
    private let downloader: any KokoroDownloading
    private let extract: @Sendable (URL, URL) throws -> Void
    /// The provider's `voices` is read nonisolated, so it reads this rather than `state`.
    private let installedFlag = Mutex(false)
    /// Bumped on cancel and remove, so a callback from a download that is no longer
    /// wanted changes nothing.
    private var generation = 0
    /// The checksum and the extraction, off the main actor. Internal so a test can wait.
    private(set) var installTask: Task<Void, Never>?

    public init(
        paths: KokoroPaths, release: KokoroReleaseInfo, downloader: any KokoroDownloading,
        extract: @escaping @Sendable (URL, URL) throws -> Void = AppleArchiveFile.extract
    ) {
        self.paths = paths
        self.release = release
        self.downloader = downloader
        self.extract = extract
    }

    public nonisolated var isInstalledNow: Bool { installedFlag.withLock { $0 } }

    private var isInstalled: Bool {
        if case .installed = state { return true }
        return false
    }

    public var installedRoot: URL? { isInstalled ? paths.modelDirectory(version: release.version) : nil }
    public var compiledCache: URL { paths.compiledCache(version: release.version) }

    /// The launch sweep: leftovers go, an installed version is found, and a download
    /// left running or interrupted is picked up where it was.
    public func start() async {
        let fm = FileManager.default
        try? fm.createDirectory(at: paths.support, withIntermediateDirectories: true)
        try? fm.removeItem(at: paths.installing)
        let versions = (try? fm.contentsOfDirectory(at: paths.support, includingPropertiesForKeys: [.isDirectoryKey])) ?? []
        for folder in versions where (try? folder.resourceValues(forKeys: [.isDirectoryKey]).isDirectory) == true {
            let version = folder.lastPathComponent
            let marked = fm.fileExists(atPath: paths.marker(version: version).path)
            if version != release.version || !marked {
                try? fm.removeItem(at: folder)
                try? fm.removeItem(at: paths.compiledCache(version: version))
            }
        }
        if fm.fileExists(atPath: paths.marker(version: release.version).path) {
            state = .installed(version: release.version, bytes: Self.size(of: paths.modelDirectory(version: release.version)))
            return
        }
        if await downloader.reattach(to: paths.archive, delegate: self) {
            state = .downloading(0)
            return
        }
        if fm.fileExists(atPath: paths.resumeData.path) { download() }
    }

    public func download() {
        guard !isInstalled else { return }
        if case .downloading = state { return }
        if case .installing = state { return }
        let resume = try? Data(contentsOf: paths.resumeData)
        try? FileManager.default.createDirectory(at: paths.support, withIntermediateDirectories: true)
        try? FileManager.default.removeItem(at: paths.archive)
        state = .downloading(0)
        downloader.download(release.url, to: paths.archive, resumeData: resume, delegate: self)
    }

    public func cancel() {
        guard case .downloading = state else { return }
        generation += 1
        downloader.cancel()
        try? FileManager.default.removeItem(at: paths.resumeData)
        try? FileManager.default.removeItem(at: paths.archive)
        state = .absent
    }

    public func remove() {
        generation += 1
        installTask?.cancel()
        try? FileManager.default.removeItem(at: paths.modelDirectory(version: release.version))
        try? FileManager.default.removeItem(at: paths.compiledCache(version: release.version))
        state = .absent
    }

    /// Checksum, extract, move into place, mark. Off the main actor: the archive is
    /// 159 MB and the reader's window must not freeze for it.
    private func install() {
        state = .installing
        let gen = generation
        let paths = paths
        let release = release
        let extract = extract
        installTask = Task.detached(priority: .userInitiated) {
            let outcome: Result<Int64, Error> = Result {
                guard try Self.sha256(of: paths.archive) == release.sha256 else { throw InstallError.mismatch }
                let fm = FileManager.default
                try? fm.removeItem(at: paths.installing)
                try extract(paths.archive, paths.installing)
                let destination = paths.modelDirectory(version: release.version)
                try? fm.removeItem(at: destination)
                try fm.moveItem(at: paths.installing, to: destination)
                try Data().write(to: paths.marker(version: release.version))
                try fm.createDirectory(at: paths.compiledCache(version: release.version), withIntermediateDirectories: true)
                var cache = paths.compiledCache(version: release.version)
                var values = URLResourceValues()
                values.isExcludedFromBackup = true
                try? cache.setResourceValues(values)
                try? fm.removeItem(at: paths.archive)
                try? fm.removeItem(at: paths.resumeData)
                return Self.size(of: destination)
            }
            await self.finishInstall(outcome, generation: gen)
        }
    }

    private func finishInstall(_ outcome: Result<Int64, Error>, generation gen: Int) {
        installTask = nil
        guard gen == generation else { return }
        switch outcome {
        case .success(let bytes):
            state = .installed(version: release.version, bytes: bytes)
            onInstalled?()
        case .failure(let error):
            try? FileManager.default.removeItem(at: paths.archive)
            try? FileManager.default.removeItem(at: paths.installing)
            try? FileManager.default.removeItem(at: paths.modelDirectory(version: release.version))
            state = .failed(Self.message(for: error))
        }
    }

    enum InstallError: Error { case mismatch }

    static func message(for error: Error) -> String {
        if error is InstallError { return mismatchMessage }
        let ns = error as NSError
        if ns.domain == NSCocoaErrorDomain && ns.code == NSFileWriteOutOfSpaceError { return diskFullMessage }
        if ns.domain == NSPOSIXErrorDomain && ns.code == Int(ENOSPC) { return diskFullMessage }
        return error.localizedDescription
    }

    nonisolated static func sha256(of url: URL) throws -> String {
        let handle = try FileHandle(forReadingFrom: url)
        defer { try? handle.close() }
        var hasher = SHA256()
        while true {
            let chunk = try handle.read(upToCount: 1 << 20) ?? Data()
            if chunk.isEmpty { break }
            hasher.update(data: chunk)
        }
        return hasher.finalize().map { String(format: "%02x", $0) }.joined()
    }

    /// The regular files under a folder, in bytes: what Settings shows beside Remove.
    nonisolated static func size(of folder: URL) -> Int64 {
        guard let e = FileManager.default.enumerator(at: folder, includingPropertiesForKeys: [.fileSizeKey, .isRegularFileKey]) else {
            return 0
        }
        var total: Int64 = 0
        for case let url as URL in e {
            let v = try? url.resourceValues(forKeys: [.fileSizeKey, .isRegularFileKey])
            if v?.isRegularFile == true { total += Int64(v?.fileSize ?? 0) }
        }
        return total
    }
}

extension KokoroStore: KokoroDownloadDelegate {
    public func downloadProgressed(_ fraction: Double) {
        guard case .downloading = state else { return }
        state = .downloading(fraction)
    }

    public func downloadFinished() {
        guard case .downloading = state else { return }
        install()
    }

    public func downloadFailed(_ failure: KokoroDownloadFailure, resumeData: Data?) {
        guard case .downloading = state else { return }
        if let resumeData {
            try? resumeData.write(to: paths.resumeData)
        } else {
            try? FileManager.default.removeItem(at: paths.resumeData)
        }
        switch failure {
        case .offline: state = .failed(Self.offlineMessage)
        case .http(let code): state = .failed("The server answered \(code).")
        case .other(let text): state = .failed(text)
        }
    }
}
```

`Synchronization.Mutex` is available from macOS 15; the package targets macOS 26.
The marker file's own bytes are zero, so it does not count toward the size the tests expect.

- [ ] **Step 4: Run the tests**

```bash
make test 2>&1 | grep -E "KokoroStoreTests|Test run" | tail -3
```

Expected: eleven passes.
If `aMatchingDownloadIsInstalled` reports `installing` after the await, `installTask` was nil when the test read it: `install()` must assign `installTask` before the detached task can run, which the code above does; check the test awaited `store.installTask` after `downloader.finish`.
If the size is off by the marker, the marker was written with content; it must be `Data()`.

- [ ] **Step 5: Check and commit**

```bash
make check 2>&1 | tail -3
git add Sources/Kokoro/KokoroStore.swift Tests/KokoroTests/KokoroStoreTests.swift
git commit -m "The Kokoro store owns the model's life on disk, checksum first and marker last"
```

---

### Task 5: The background downloader

**Files:**
- Create: `Sources/Kokoro/URLSessionKokoroDownloader.swift`

**Interfaces:**
- Consumes: `KokoroDownloading`, `KokoroDownloadDelegate`, `KokoroDownloadFailure` from Task 4.
- Produces: `public final class URLSessionKokoroDownloader: NSObject, KokoroDownloading, URLSessionDownloadDelegate`, `public init(identifier: String = "design.kevxu.aloud.kokoro")`.

A background session survives the window closing and the app quitting; the store's `reattach` at launch finds the task again.
There is no unit test for this class: a background session cannot be stubbed, and the store's behaviour around it is covered by the fake.
It is exercised by hand in Task 11 and by the gated integration path.

- [ ] **Step 1: Implement it**

Create `Sources/Kokoro/URLSessionKokoroDownloader.swift`:

```swift
import Foundation

/// The real downloader: one background `URLSession`, so the 159 MB keeps arriving with
/// the window closed and even with the app quit, and a launch that finds the task still
/// running picks it up. Delegate callbacks arrive on the session's queue and are hopped
/// to the main actor; the finished file is moved before the callback returns, as the
/// session requires.
public final class URLSessionKokoroDownloader: NSObject, KokoroDownloading, URLSessionDownloadDelegate {
    private let identifier: String
    private let lock = NSLock()
    private var session: URLSession?
    private var task: URLSessionDownloadTask?
    private var destination: URL?
    private weak var delegate: (any KokoroDownloadDelegate)?

    public init(identifier: String = "design.kevxu.aloud.kokoro") {
        self.identifier = identifier
        super.init()
    }

    private func makeSession() -> URLSession {
        lock.lock()
        defer { lock.unlock() }
        if let session { return session }
        let configuration = URLSessionConfiguration.background(withIdentifier: identifier)
        configuration.isDiscretionary = false
        configuration.sessionSendsLaunchEvents = false
        let s = URLSession(configuration: configuration, delegate: self, delegateQueue: nil)
        session = s
        return s
    }

    public func download(_ url: URL, to destination: URL, resumeData: Data?, delegate: any KokoroDownloadDelegate) {
        let session = makeSession()
        lock.lock()
        self.destination = destination
        self.delegate = delegate
        let t = resumeData.map { session.downloadTask(withResumeData: $0) } ?? session.downloadTask(with: url)
        task = t
        lock.unlock()
        t.resume()
    }

    public func reattach(to destination: URL, delegate: any KokoroDownloadDelegate) async -> Bool {
        let session = makeSession()
        let tasks = await session.allTasks
        guard let running = tasks.compactMap({ $0 as? URLSessionDownloadTask }).first(where: { $0.state == .running }) else {
            return false
        }
        lock.lock()
        self.destination = destination
        self.delegate = delegate
        task = running
        lock.unlock()
        return true
    }

    public func cancel() {
        lock.lock()
        let t = task
        task = nil
        lock.unlock()
        t?.cancel()
    }

    private func current() -> (URL?, (any KokoroDownloadDelegate)?) {
        lock.lock()
        defer { lock.unlock() }
        return (destination, delegate)
    }

    public func urlSession(
        _ session: URLSession, downloadTask: URLSessionDownloadTask, didWriteData bytesWritten: Int64,
        totalBytesWritten: Int64, totalBytesExpectedToWrite: Int64
    ) {
        guard totalBytesExpectedToWrite > 0 else { return }
        let fraction = Double(totalBytesWritten) / Double(totalBytesExpectedToWrite)
        let (_, delegate) = current()
        Task { @MainActor in delegate?.downloadProgressed(min(max(fraction, 0), 1)) }
    }

    public func urlSession(_ session: URLSession, downloadTask: URLSessionDownloadTask, didFinishDownloadingTo location: URL) {
        let (destination, delegate) = current()
        guard let destination else { return }
        // The temporary file is gone once this returns, so the move happens here.
        let moved: Result<Void, Error> = Result {
            if let http = downloadTask.response as? HTTPURLResponse, http.statusCode != 200 {
                throw URLError(.badServerResponse, userInfo: ["status": http.statusCode])
            }
            try? FileManager.default.removeItem(at: destination)
            try FileManager.default.createDirectory(
                at: destination.deletingLastPathComponent(), withIntermediateDirectories: true)
            try FileManager.default.moveItem(at: location, to: destination)
        }
        Task { @MainActor in
            switch moved {
            case .success: delegate?.downloadFinished()
            case .failure(let error): delegate?.downloadFailed(Self.failure(for: error, task: downloadTask), resumeData: nil)
            }
        }
    }

    public func urlSession(_ session: URLSession, task: URLSessionTask, didCompleteWithError error: Error?) {
        guard let error else { return }
        let ns = error as NSError
        // A cancel from the store is the store's own doing and is not reported back.
        if ns.domain == NSURLErrorDomain && ns.code == NSURLErrorCancelled { return }
        let resume = ns.userInfo[NSURLSessionDownloadTaskResumeData] as? Data
        let (_, delegate) = current()
        let failure = Self.failure(for: error, task: task)
        Task { @MainActor in delegate?.downloadFailed(failure, resumeData: resume) }
    }

    static func failure(for error: Error, task: URLSessionTask) -> KokoroDownloadFailure {
        let ns = error as NSError
        if ns.domain == NSURLErrorDomain,
            [NSURLErrorNotConnectedToInternet, NSURLErrorNetworkConnectionLost, NSURLErrorCannotFindHost,
                NSURLErrorCannotConnectToHost, NSURLErrorDNSLookupFailed, NSURLErrorTimedOut].contains(ns.code)
        {
            return .offline
        }
        if let http = task.response as? HTTPURLResponse, http.statusCode != 200 { return .http(http.statusCode) }
        if let status = ns.userInfo["status"] as? Int { return .http(status) }
        return .other(error.localizedDescription)
    }
}
```

`KokoroDownloading` is `Sendable`; the class is `NSObject` with every mutable field behind the lock, so add `extension URLSessionKokoroDownloader: @unchecked Sendable {}` at the bottom of the file with a one-line comment saying the lock is what makes it so.

- [ ] **Step 2: Build**

```bash
swift build 2>&1 | grep -E "error:|warning:" | head -5
```

Expected: nothing.
If the compiler objects that the delegate methods are not `nonisolated`, mark each `public nonisolated func urlSession(...)`; the class is not actor-isolated, so this is only needed if a global actor inference applies.

- [ ] **Step 3: Check and commit**

```bash
make check 2>&1 | tail -3
git add Sources/Kokoro/URLSessionKokoroDownloader.swift
git commit -m "The model downloads in a background session that outlives the window"
```

---

### Task 6: The engine actor and the audio player

**Files:**
- Create: `Sources/Kokoro/KokoroEngine.swift`
- Create: `Sources/Kokoro/KokoroPlayback.swift`

**Interfaces:**
- Produces:

```swift
public enum KokoroEngineError: Error, Sendable, Equatable {
  case notLoaded, load(String), synthesis(String), cancelled, nothingToSay
}
public protocol KokoroSynthesizing: Actor {
  func load(root: URL, cache: URL) async throws
  func synthesize(_ text: String, voice: String, speed: Double) async throws -> [Float]
  func unload()
}
public actor KokoroEngine: KokoroSynthesizing { public init(); public var isLoaded: Bool }
@MainActor public protocol KokoroPlaying: AnyObject {
  func play(_ samples: [Float], volume: Double, completion: @escaping @MainActor () -> Void)
  func stop()
}
@MainActor public final class KokoroPlayback: KokoroPlaying { public init() }
```

Neither has a unit test of its own: one wraps CoreML and the other real audio hardware.
The provider is tested against fakes of both protocols, and the gated integration test in Task 11 runs the real engine.

- [ ] **Step 1: Write the engine**

Create `Sources/Kokoro/KokoroEngine.swift`:

```swift
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
        do {
            let audio = try await tts.synthesize(
                text, voice: KokoroVoiceID(voice), options: KokoroSynthesisOptions(speed: Float(speed)))
            return audio.samples
        } catch is CancellationError {
            throw KokoroEngineError.cancelled
        } catch KokoroError.synthesisCancelled {
            throw KokoroEngineError.cancelled
        } catch KokoroError.emptyText, KokoroError.emptyPhonemizerOutput {
            throw KokoroEngineError.nothingToSay
        } catch KokoroError.inaudibleChunk {
            throw KokoroEngineError.nothingToSay
        } catch {
            throw KokoroEngineError.synthesis(error.localizedDescription)
        }
    }

    public func unload() { tts = nil }
}
```

If the compiler wants the associated values spelled in the `inaudibleChunk` pattern, write `catch KokoroError.inaudibleChunk(characters: _, droppedTokens: _)`.

- [ ] **Step 2: Write the player**

Create `Sources/Kokoro/KokoroPlayback.swift`:

```swift
import AVFoundation
import Foundation

/// Plays one buffer of samples and says when it has been heard, so a fake can stand in.
@MainActor
public protocol KokoroPlaying: AnyObject {
    func play(_ samples: [Float], volume: Double, completion: @escaping @MainActor () -> Void)
    func stop()
}

/// An audio engine with one player node at the model's 24 kHz mono. A new buffer
/// replaces whatever is playing. The engine is restarted when the output device
/// changes, so an unplugged headphone set does not leave it silent.
@MainActor
public final class KokoroPlayback: KokoroPlaying {
    public static let sampleRate: Double = 24000

    private let engine = AVAudioEngine()
    private let node = AVAudioPlayerNode()
    private let format = AVAudioFormat(standardFormatWithSampleRate: KokoroPlayback.sampleRate, channels: 1)!
    /// A completion from a buffer that was replaced or stopped is not the current one's.
    private var generation = 0
    private var observer: (any NSObjectProtocol)?

    public init() {
        engine.attach(node)
        engine.connect(node, to: engine.mainMixerNode, format: format)
        observer = NotificationCenter.default.addObserver(
            forName: .AVAudioEngineConfigurationChange, object: engine, queue: .main
        ) { [weak self] _ in
            // The engine has stopped itself; the next play starts it again with the new
            // device. Whatever was in the air is lost, and the model pauses on the same
            // change, so nothing is resumed here.
            MainActor.assumeIsolated { self?.generation += 1 }
        }
    }

    deinit {
        if let observer { NotificationCenter.default.removeObserver(observer) }
    }

    public func play(_ samples: [Float], volume: Double, completion: @escaping @MainActor () -> Void) {
        node.stop()
        generation += 1
        let gen = generation
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
        guard let buffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: AVAudioFrameCount(samples.count)),
            let channel = buffer.floatChannelData?[0]
        else {
            completion()
            return
        }
        samples.withUnsafeBufferPointer { channel.update(from: $0.baseAddress!, count: samples.count) }
        buffer.frameLength = AVAudioFrameCount(samples.count)
        node.volume = Float(min(max(volume, 0), 1))
        node.scheduleBuffer(buffer, completionCallbackType: .dataPlayedBack) { _ in
            Task { @MainActor [weak self] in
                guard let self, gen == self.generation else { return }
                completion()
            }
        }
        node.play()
    }

    public func stop() {
        generation += 1
        node.stop()
    }
}
```

- [ ] **Step 3: Build**

```bash
swift build 2>&1 | grep -E "error:|warning:" | head -5
```

Expected: nothing.
If `MainActor.assumeIsolated` in the notification handler is refused because the closure is `@Sendable`, replace the body with `Task { @MainActor [weak self] in self?.generation += 1 }`.

- [ ] **Step 4: Check and commit**

```bash
make check 2>&1 | tail -3
git add Sources/Kokoro/KokoroEngine.swift Sources/Kokoro/KokoroPlayback.swift
git commit -m "An actor over the Kokoro SDK, and a player for its samples"
```

---

### Task 7: The Kokoro voice provider

**Files:**
- Create: `Sources/Kokoro/KokoroVoiceProvider.swift`
- Test: `Tests/KokoroTests/KokoroVoiceProviderTests.swift`

**Interfaces:**
- Consumes: `KokoroStore`, `KokoroSynthesizing`, `KokoroPlaying`, `KokoroCatalogue`, `VoiceProvider`.
- Produces:

```swift
@MainActor public final class KokoroVoiceProvider: VoiceProvider {
  public let store: KokoroStore
  public private(set) var isWarming: Bool
  public private(set) var isLoaded: Bool
  public var onLoadFailure: (@MainActor (String) -> Void)?
  public init(store: KokoroStore, engine: any KokoroSynthesizing = KokoroEngine(), playback: any KokoroPlaying = KokoroPlayback(),
              sleep: @escaping @Sendable (Duration) async throws -> Void = { try await Task.sleep(for: $0) })
  public func warm()
  public func unload()
  var speakTask: Task<Void, Never>?      // internal, for tests
  var pauseTask: Task<Void, Never>?
  var warmTask: Task<Void, Never>?
  var previewTask: Task<Void, Never>?
}
```

- [ ] **Step 1: Write the failing tests**

Create `Tests/KokoroTests/KokoroVoiceProviderTests.swift`:

```swift
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

    func make(installed: Bool = true) throws -> (KokoroVoiceProvider, FakeEngine, FakePlayback, HeldSleep, KokoroStore) {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        let paths = KokoroPaths(support: root.appendingPathComponent("s"), caches: root.appendingPathComponent("c"))
        if installed {
            try FileManager.default.createDirectory(at: paths.modelDirectory(version: "1"), withIntermediateDirectories: true)
            try Data().write(to: paths.marker(version: "1"))
        }
        let store = KokoroStore(paths: paths, release: KokoroRelease.current, downloader: FakeDownloader())
        let engine = FakeEngine()
        let playback = FakePlayback()
        let held = HeldSleep()
        let provider = KokoroVoiceProvider(store: store, engine: engine, playback: playback) { try await held.sleep($0) }
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
        p.speak("Nobody really teaches you research.", voice: bella, rate: .x15, pause: .milliseconds(200), volume: 0.5,
            onWord: { _ in words += 1 }, onFinish: { finished += 1 })
        #expect(await until { playback.played.count == 1 })
        #expect(await engine.calls == [.init(text: "Nobody really teaches you research.", voice: "af_bella", speed: 1.5)])
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
        p.speak("One.", voice: bella, rate: .x1, pause: .milliseconds(100), volume: 1, onWord: { _ in }, onFinish: { finished += 1 })
        #expect(await eventually { await engine.calls.count == 1 })
        p.stop()
        await engine.release()
        await p.speakTask?.value
        #expect(playback.played.isEmpty)
        #expect(playback.stops == 1)
        // A sentence that was already playing: its completion arrives after the stop.
        p.speak("Two.", voice: bella, rate: .x1, pause: .zero, volume: 1, onWord: { _ in }, onFinish: { finished += 1 })
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
        p.speak("***", voice: bella, rate: .x1, pause: .milliseconds(50), volume: 1, onWord: { _ in }, onFinish: { finished += 1 })
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
```

`FakeDownloader` is the one from `KokoroStoreTests.swift`; both files are in the same test module.

- [ ] **Step 2: Run to see them fail**

```bash
make test 2>&1 | grep -E "error:" | head -3
```

Expected: `cannot find 'KokoroVoiceProvider' in scope`.

- [ ] **Step 3: Implement the provider**

Create `Sources/Kokoro/KokoroVoiceProvider.swift`:

```swift
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
        prepared = (key, Task { try? await engine.synthesize(text, voice: kokoro.kokoroID, speed: rate.factor) })
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
            guard let samples = await samples(for: VoicePreview.text, voice: kokoro, rate: .x1), gen == generation else {
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
            log.error("Kokoro could not speak a sentence: \((error as? KokoroEngineError).map(Self.text) ?? error.localizedDescription, privacy: .public)")
            return nil
        }
    }

    private func finish(after pause: Duration, generation gen: Int, _ onFinish: @escaping @MainActor () -> Void) {
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
```

The `nonisolated var voices` reads `store.isInstalledNow`, which is the store's lock-guarded snapshot, and never touches main-actor state.

- [ ] **Step 4: Run the tests**

```bash
make test 2>&1 | grep -E "KokoroVoiceProviderTests|Test run" | tail -3
```

Expected: ten passes.
If `stopCancelsAndGuardsLateCompletions` flakes on its first `eventually`, the fake's `hold()` raced the speak task: call `await engine.hold()` before `warm()` in that test.

- [ ] **Step 5: Check and commit**

```bash
make check 2>&1 | tail -3
git add Sources/Kokoro/KokoroVoiceProvider.swift Tests/KokoroTests/KokoroVoiceProviderTests.swift
git commit -m "A Kokoro voice provider: rendered ahead, played, paused and guarded by generation"
```

---

### Task 8: The row's busy and dimmed states, the download banner, and the tokens

**Files:**
- Modify: `Sources/AloudUI/Tokens.swift`
- Modify: `Sources/AloudUI/Components/VoiceRow.swift`
- Create: `Sources/AloudUI/Components/DownloadBanner.swift`
- Modify: `Sources/AloudUI/Gallery.swift`
- Test: `Tests/AloudUITests/DownloadBannerTests.swift`

**Interfaces:**
- Produces:

```swift
// Tokens
public enum Motion { public static let opaque: Double = 1 }          // added
public enum Copy {                                                     // new namespace
  static let kokoroSection = "Kokoro"
  static let kokoroCaption = "Seven voices, one download of about 160 MB, runs on your Mac."
  static let kokoroInstalling = "Installing"
  static let cancel = "Cancel"; retry = "Retry"; download = "Download"; remove = "Remove"
  static let kokoroSettingsLabel = "Kokoro voices"
  static let kokoroAbsent = "Not downloaded"
  static func kokoroInstalled(version: String, size: String) -> String   // "Version 1, 159 MB"
}
// VoiceRow gains two props with defaults:
isBusy: Bool = false      // a spinner in place of the play icon
isDimmed: Bool = false    // half opacity and no interaction
// DownloadBanner
public struct DownloadBanner: View {
  public enum Phase: Equatable { case idle(String), progress(Double), busy(String), failed(String) }
  public init(title: String, phase: Phase, onCancel: @escaping () -> Void, onRetry: @escaping () -> Void)
}
```

- [ ] **Step 1: Write the failing test**

Create `Tests/AloudUITests/DownloadBannerTests.swift`:

```swift
import SwiftUI
import Testing

@testable import AloudUI

@Suite @MainActor struct DownloadBannerTests {
    /// Every phase builds, and the strings the app shows are the spec's.
    @Test func everyPhaseBuildsAndTheCopyIsTheSpecs() {
        for phase in [
            DownloadBanner.Phase.idle(Copy.kokoroCaption), .progress(0.4), .busy(Copy.kokoroInstalling),
            .failed("No internet connection."),
        ] {
            _ = DownloadBanner(title: Copy.kokoroSection, phase: phase, onCancel: {}, onRetry: {}).body
        }
        #expect(Copy.kokoroSection == "Kokoro")
        #expect(Copy.kokoroCaption.hasPrefix("Seven voices, one download of about "))
        #expect(Copy.kokoroCaption.hasSuffix(" MB, runs on your Mac."))
        #expect(Copy.cancel == "Cancel" && Copy.retry == "Retry" && Copy.download == "Download" && Copy.remove == "Remove")
        #expect(Copy.kokoroInstalled(version: "1", size: "159 MB") == "Version 1, 159 MB")
    }

    @Test func aBusyOrDimmedRowBuilds() {
        _ = VoiceRow(
            name: "Bella", region: "United States", quality: "Premium", isSelected: true, isBusy: true,
            onPreview: {}, onPick: {}
        ).body
        _ = VoiceRow(
            name: "Bella", region: "United States", quality: "Premium", badge: "159 MB", isSelected: false,
            isInstalled: false, isDimmed: true, onPreview: {}, onPick: {}
        ).body
        #expect(Gallery.sections.contains("DownloadBanner"))
    }
}
```

- [ ] **Step 2: Run to see it fail**

```bash
make test 2>&1 | grep -E "error:" | head -3
```

Expected: `cannot find 'DownloadBanner' in scope`.

- [ ] **Step 3: Add the tokens**

In `Sources/AloudUI/Tokens.swift`, add to `Motion` after `dimmed`:

```swift
    /// Fully drawn: the other end of `dimmed`.
    public static let opaque: Double = 1
```

Add at the end of the file:

```swift
/// The copy the Kokoro section introduces. The spec asks for every string the section
/// adds to live here, beside the sizes, so the words can be read in one place.
public enum Copy {
    public static let kokoroSection = "Kokoro"
    public static let kokoroCaption = "Seven voices, one download of about 160 MB, runs on your Mac."
    public static let kokoroInstalling = "Installing"
    public static let cancel = "Cancel"
    public static let retry = "Retry"
    public static let download = "Download"
    public static let remove = "Remove"
    public static let kokoroSettingsLabel = "Kokoro voices"
    public static let kokoroAbsent = "Not downloaded"
    public static func kokoroInstalled(version: String, size: String) -> String { "Version \(version), \(size)" }
}
```

If plan 2's archive rounds to a different number of megabytes, write that number in `kokoroCaption` (to the nearest 5 MB) and nowhere else.

- [ ] **Step 4: Give the row its two states**

In `Sources/AloudUI/Components/VoiceRow.swift`, add two stored properties after `isInstalled`:

```swift
    let isBusy: Bool
    let isDimmed: Bool
```

Change the initializer to:

```swift
    public init(
        name: String, region: String?, quality: String, badge: String? = nil,
        isSelected: Bool, isInstalled: Bool = true, isBusy: Bool = false, isDimmed: Bool = false,
        onPreview: @escaping () -> Void, onPick: @escaping () -> Void
    ) {
        self.name = name
        self.region = region
        self.quality = quality
        self.badge = badge
        self.isSelected = isSelected
        self.isInstalled = isInstalled
        self.isBusy = isBusy
        self.isDimmed = isDimmed
        self.onPreview = onPreview
        self.onPick = onPick
    }
```

Replace the leading button in `body`:

```swift
            Button(action: isInstalled ? onPreview : onPick) {
                Image(systemName: isInstalled ? "play.circle" : "arrow.down.circle")
            }
            .buttonStyle(.borderless)
            .accessibilityLabel(isInstalled ? "Preview \(name)" : "Download \(name)")
```

with:

```swift
            // While the models load for a just-picked voice the play icon gives way to a
            // spinner; the row is still the row, so its width does not change.
            if isBusy {
                ProgressView()
                    .controlSize(.small)
                    .frame(width: Size.icon, height: Size.icon)
                    .accessibilityLabel("Loading \(name)")
            } else {
                Button(action: isInstalled ? onPreview : onPick) {
                    Image(systemName: isInstalled ? "play.circle" : "arrow.down.circle")
                }
                .buttonStyle(.borderless)
                .accessibilityLabel(isInstalled ? "Preview \(name)" : "Download \(name)")
            }
```

and change the closing `.padding(.vertical, Space.s)` to:

```swift
        .padding(.vertical, Space.s)
        .opacity(isDimmed ? Motion.dimmed : Motion.opaque)
        .disabled(isDimmed)
```

Check `Size.icon` exists in `Tokens.swift` (it does, at 16); use it rather than a new token.

- [ ] **Step 5: Write the banner**

Create `Sources/AloudUI/Components/DownloadBanner.swift`:

```swift
import SwiftUI

/// The header of a section whose voices come as one download: the title, and under
/// it the caption, the progress with Cancel, the installing spinner, or the failure
/// with Retry. Pure: strings and closures in, no model.
public struct DownloadBanner: View {
    public enum Phase: Equatable {
        case idle(String)
        case progress(Double)
        case busy(String)
        case failed(String)
    }

    let title: String
    let phase: Phase
    let onCancel: () -> Void
    let onRetry: () -> Void

    public init(title: String, phase: Phase, onCancel: @escaping () -> Void, onRetry: @escaping () -> Void) {
        self.title = title
        self.phase = phase
        self.onCancel = onCancel
        self.onRetry = onRetry
    }

    public var body: some View {
        VStack(alignment: .leading, spacing: Space.xs) {
            Text(title).font(Type.caption).foregroundStyle(Ink.soft)
            switch phase {
            case .idle(let caption):
                Text(caption)
                    .font(Type.caption)
                    .foregroundStyle(Ink.soft)
                    .fixedSize(horizontal: false, vertical: true)
            case .progress(let fraction):
                HStack(spacing: Space.s) {
                    ProgressView(value: fraction)
                        .progressViewStyle(.linear)
                        .accessibilityLabel("Downloading")
                    Button(Copy.cancel, action: onCancel).buttonStyle(.link)
                }
            case .busy(let word):
                HStack(spacing: Space.s) {
                    ProgressView().controlSize(.small)
                    Text(word).font(Type.caption).foregroundStyle(Ink.soft)
                }
            case .failed(let message):
                HStack(alignment: .firstTextBaseline, spacing: Space.s) {
                    Text(message)
                        .font(Type.caption)
                        .foregroundStyle(Ink.soft)
                        .fixedSize(horizontal: false, vertical: true)
                    Button(Copy.retry, action: onRetry).buttonStyle(.link)
                }
            }
        }
    }
}
```

- [ ] **Step 6: Show both in the gallery**

In `Sources/AloudUI/Gallery.swift`, add `"DownloadBanner"` to `sections` after `"VoiceRow"`, add two rows to the `VoiceRow` section's `VStack`:

```swift
                        VoiceRow(
                            name: "Bella", region: "United States", quality: "Premium",
                            isSelected: true, isBusy: true, onPreview: {}, onPick: {})
                        VoiceRow(
                            name: "Fable", region: "United Kingdom", quality: "Premium",
                            badge: "159 MB", isSelected: false, isInstalled: false, isDimmed: true,
                            onPreview: {}, onPick: {})
```

and a new section after it:

```swift
                section("DownloadBanner") {
                    VStack(alignment: .leading, spacing: Space.l) {
                        DownloadBanner(
                            title: Copy.kokoroSection, phase: .idle(Copy.kokoroCaption), onCancel: {}, onRetry: {})
                        DownloadBanner(title: Copy.kokoroSection, phase: .progress(0.4), onCancel: {}, onRetry: {})
                        DownloadBanner(
                            title: Copy.kokoroSection, phase: .busy(Copy.kokoroInstalling), onCancel: {}, onRetry: {})
                        DownloadBanner(
                            title: Copy.kokoroSection, phase: .failed("No internet connection."), onCancel: {},
                            onRetry: {})
                    }
                    .frame(width: Size.popoverWidth)
                }
```

`0.4` is a value, not a size, and passes the lint; `Size.popoverWidth` keeps the banner at the popover's width.

- [ ] **Step 7: Run the tests and look at the gallery**

```bash
make test 2>&1 | grep -E "DownloadBannerTests|LiteralLintTests|GalleryTests|Test run" | tail -4
make gallery
```

Expected: the three suites pass, and the gallery shows the busy row with a small spinner where the play icon was, the dimmed row at half opacity, and the four banner states with the progress bar and Cancel on one line.
Be picky: the spinner must not move the name to the right of where the other rows' names sit, and the failed banner's Retry must sit on the message's baseline.

- [ ] **Step 8: Check and commit**

```bash
make check 2>&1 | tail -3
git add Sources/AloudUI Tests/AloudUITests/DownloadBannerTests.swift
git commit -m "A voice row can be busy or dimmed, and a section header can carry a download"
```

---

### Task 9: Wiring the app: one composite provider, the store on the model, warm and unload on pick

**Files:**
- Modify: `Sources/Aloud/AloudApp.swift:37-47`
- Modify: `Sources/Aloud/AppModel.swift` (`init`, `pickVoice`, `start`)
- Test: `Tests/AloudTests/AppModelTests.swift`

**Interfaces:**
- Produces on `AppModel`:

```swift
let kokoro: KokoroVoiceProvider?          // nil under --silent
var kokoroStore: KokoroStore? { kokoro?.store }
var pendingKokoroPick: Voice?             // the row clicked before the download; taken when the install completes
func downloadKokoro(picking voice: Voice?)
func cancelKokoroDownload()
func removeKokoro()
// init gains `kokoro: KokoroVoiceProvider? = nil`
```

- [ ] **Step 1: Write the failing tests**

Add to `Tests/AloudTests/AppModelTests.swift`, inside the suite:

```swift
    /// A model with a Kokoro provider over a store the test controls: nothing installed
    /// unless the case installs it.
    func withKokoroModel(_ body: (AppModel, KokoroVoiceProvider, KokoroStore, FakeDownloader) async throws -> Void)
        async throws
    {
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        let name = "design.aloud.tests.\(UUID().uuidString)"
        let suite = UserDefaults(suiteName: name)!
        defer {
            suite.removePersistentDomain(forName: name)
            try? FileManager.default.removeItem(at: dir)
        }
        let paths = KokoroPaths(support: dir.appendingPathComponent("s"), caches: dir.appendingPathComponent("c"))
        let downloader = FakeDownloader()
        let store = KokoroStore(paths: paths, release: KokoroRelease.current, downloader: downloader)
        let engine = FakeEngine()
        let kokoro = KokoroVoiceProvider(store: store, engine: engine, playback: FakePlayback())
        let apple = FakeVoiceProvider()
        let composite = CompositeVoiceProvider(primary: apple, secondary: kokoro, secondaryPrefix: KokoroCatalogue.prefix)
        let model = AppModel(
            provider: composite, kokoro: kokoro,
            progress: ProgressStore(file: dir.appendingPathComponent("progress.json")),
            rootStore: RootStore(defaults: suite), notesFolder: dir, emptyPanelHold: .seconds(1))
        try await body(model, kokoro, store, downloader)
    }

    /// Picking a Kokoro voice loads the models; picking an Apple voice again gives the
    /// memory back.
    @Test func pickingAKokoroVoiceWarmsAndAnAppleVoiceUnloads() async throws {
        try await withKokoroModel { model, kokoro, store, _ in
            try FileManager.default.createDirectory(at: store.paths.modelDirectory(version: "1"), withIntermediateDirectories: true)
            try Data().write(to: store.paths.marker(version: "1"))
            await store.start()
            let bella = try #require(model.provider.voices.first { $0.id == "kokoro.af_bella" })
            model.pickVoice(bella)
            #expect(kokoro.isWarming || kokoro.isLoaded)
            await kokoro.warmTask?.value
            #expect(kokoro.isLoaded)
            #expect(model.player.voice?.id == "kokoro.af_bella")
            model.pickVoice(try #require(model.provider.voices.first { $0.id == "fake" }))
            #expect(!kokoro.isLoaded)
        }
    }

    /// A row clicked before the download is the pick that takes when the install
    /// completes, so the reader's intent needs no second click.
    @Test func theRowClickedBeforeTheDownloadIsPickedAfterIt() async throws {
        try await withKokoroModel { model, kokoro, store, downloader in
            await store.start()
            let fable = KokoroCatalogue.voices[6].voice
            model.downloadKokoro(picking: fable)
            #expect(store.state == .downloading(0))
            #expect(model.pendingKokoroPick?.id == "kokoro.bm_fable")
            // The store's install needs a real archive; a marker written by hand and a
            // direct completion stand in for the 159 MB.
            try FileManager.default.createDirectory(at: store.paths.modelDirectory(version: "1"), withIntermediateDirectories: true)
            try Data().write(to: store.paths.marker(version: "1"))
            await store.start()
            store.onInstalled?()
            #expect(model.player.voice?.id == "kokoro.bm_fable")
            #expect(model.pendingKokoroPick == nil)
            await kokoro.warmTask?.value
            #expect(kokoro.isLoaded)
        }
    }

    @Test func cancelAndRemoveReachTheStore() async throws {
        try await withKokoroModel { model, _, store, downloader in
            await store.start()
            model.downloadKokoro(picking: nil)
            model.cancelKokoroDownload()
            #expect(store.state == .absent)
            #expect(downloader.cancels == 1)
            try FileManager.default.createDirectory(at: store.paths.modelDirectory(version: "1"), withIntermediateDirectories: true)
            try Data().write(to: store.paths.marker(version: "1"))
            await store.start()
            model.pickVoice(KokoroCatalogue.voices[0].voice)
            model.removeKokoro()
            #expect(store.state == .absent)
            // The picked voice has gone with the model; the player is back on the system voice.
            #expect(model.player.voice?.id == "fake")
            #expect(model.notice?.contains("not available") == true)
        }
    }

    /// The models failing to load is said once, and the reading goes on in the system voice.
    @Test func aLoadFailureFallsBackWithANotice() async throws {
        try await withKokoroModel { model, kokoro, store, _ in
            try FileManager.default.createDirectory(at: store.paths.modelDirectory(version: "1"), withIntermediateDirectories: true)
            try Data().write(to: store.paths.marker(version: "1"))
            await store.start()
            kokoro.onLoadFailure?("no metal")
            #expect(model.player.voice?.id == "fake")
            #expect(model.notice == "Kokoro voices could not be loaded: no metal. Using the system voice.")
        }
    }
```

Add `import Kokoro` and `@testable import Kokoro` is not needed: the test uses public API, so `import Kokoro` at the top of the file is enough, plus `import Speech` (already there).
`FakeDownloader`, `FakeEngine` and `FakePlayback` live in `KokoroTests`; copy them into `Tests/AloudTests/KokoroFakes.swift` (the three types, verbatim from Task 4 and Task 7), since test targets do not share sources.

- [ ] **Step 2: Run to see them fail**

```bash
make test 2>&1 | grep -E "error:" | head -3
```

Expected: `extra argument 'kokoro' in call`.

- [ ] **Step 3: Build the providers in the app**

In `Sources/Aloud/AloudApp.swift`, add `import Kokoro` to the imports, and replace the model construction inside `init()`:

```swift
        let m = MainActor.assumeIsolated {
            AppModel(
                provider: Self.args.contains("--silent") ? FakeVoiceProvider() : AppleVoiceProvider())
        }
```

with:

```swift
        // One provider for the player and the picker, two engines behind it. `--silent`
        // keeps the fake alone, so UI work never touches audio or the model store.
        let m = MainActor.assumeIsolated {
            if Self.args.contains("--silent") {
                return AppModel(provider: FakeVoiceProvider())
            }
            let store = KokoroStore(
                paths: .standard(), release: KokoroRelease.current, downloader: URLSessionKokoroDownloader())
            let kokoro = KokoroVoiceProvider(store: store)
            let composite = CompositeVoiceProvider(
                primary: AppleVoiceProvider(), secondary: kokoro, secondaryPrefix: KokoroCatalogue.prefix)
            return AppModel(provider: composite, kokoro: kokoro)
        }
```

- [ ] **Step 4: Teach the model**

In `Sources/Aloud/AppModel.swift`, add `import Kokoro`. Add a stored property after `let provider: any VoiceProvider`:

```swift
    /// The second engine, when the app has one. Nil under `--silent`.
    let kokoro: KokoroVoiceProvider?
    var kokoroStore: KokoroStore? { kokoro?.store }
    /// The Kokoro row clicked before the model was downloaded: picked when the install
    /// completes, so the click that started the download is the pick.
    var pendingKokoroPick: Voice?
```

Change the `init` signature to add `kokoro: KokoroVoiceProvider? = nil` after `provider:`, assign `self.kokoro = kokoro` beside `self.provider = provider`, and add at the end of `init`, after the `player.onFinished` assignment:

```swift
        kokoro?.onLoadFailure = { [weak self] message in
            guard let self else { return }
            // The provider's list is empty now; the player's own check falls back and
            // posts its own notice, which this one then says more about.
            self.player.revalidateVoice()
            self.notice = "Kokoro voices could not be loaded: \(message). Using the system voice."
        }
        kokoro?.store.onInstalled = { [weak self] in
            guard let self else { return }
            if let v = self.pendingKokoroPick {
                self.pendingKokoroPick = nil
                self.pickVoice(v)
            }
        }
```

Replace `pickVoice`:

```swift
    /// The one writer of `player.voice` after init, so the choice and what is
    /// remembered can never disagree. It takes at the next sentence. A Kokoro voice
    /// loads its models now, so the first sentence does not wait; an Apple voice gives
    /// that memory back.
    func pickVoice(_ v: Voice) {
        player.voice = v
        Defaults.voiceID = v.id
        if KokoroCatalogue.isKokoro(v.id) {
            kokoro?.warm()
        } else {
            kokoro?.unload()
        }
    }
```

Add three methods after it:

```swift
    /// Starts the one download. `voice` is the row that was clicked, picked once the
    /// install completes; nil from Settings, where no row was.
    func downloadKokoro(picking voice: Voice?) {
        pendingKokoroPick = voice
        kokoroStore?.download()
    }

    func cancelKokoroDownload() {
        pendingKokoroPick = nil
        kokoroStore?.cancel()
    }

    /// Removes the model. A Kokoro voice that was picked is gone with it, and the
    /// player falls back through its own check.
    func removeKokoro() {
        kokoro?.unload()
        kokoroStore?.remove()
        player.revalidateVoice()
    }
```

In `start()`, after `clipboard.watch()`:

```swift
        Task {
            await kokoroStore?.start()
            // The saved voice was a Kokoro one and the model is here: load it now, so
            // Play does not wait.
            if let v = player.voice, KokoroCatalogue.isKokoro(v.id) { kokoro?.warm() }
        }
```

The launch-time lookup in `init` (`Defaults.voiceID` against `provider.voices`) runs before the store has started, when the Kokoro provider's list is empty, so a saved Kokoro voice would be dropped there.
Move that lookup: leave the `init` line as it is for Apple voices, and in the `Task` above, after `start()`, add:

```swift
            if let id = Defaults.voiceID, KokoroCatalogue.isKokoro(id),
                let v = provider.voices.first(where: { $0.id == id })
            {
                player.voice = v
                kokoro?.warm()
            }
```

- [ ] **Step 5: Run the tests**

```bash
make test 2>&1 | grep -E "AppModelTests|Test run" | tail -3
```

Expected: the four new tests pass with the rest of the suite.
`removeKokoro` in `cancelAndRemoveReachTheStore` relies on `store.remove()` flipping the installed flag before `revalidateVoice()` reads `provider.voices`, which the store's `didSet` does synchronously.

- [ ] **Step 6: Check and commit**

```bash
make check 2>&1 | tail -3
git add Sources/Aloud/AloudApp.swift Sources/Aloud/AppModel.swift Tests/AloudTests/AppModelTests.swift Tests/AloudTests/KokoroFakes.swift
git commit -m "The app speaks through one provider over two engines, and a pick warms or unloads Kokoro"
```

---

### Task 10: The Kokoro section in the picker

**Files:**
- Modify: `Sources/Aloud/VoicePopover.swift`

**Interfaces:**
- Consumes: `AppModel.kokoro`, `AppModel.kokoroStore`, `KokoroCatalogue.regions`, `DownloadBanner`, `VoiceRow(isBusy:isDimmed:)`, `Copy`.

There is no unit test for a SwiftUI body; the section is checked by eye in Step 4 and its logic lives in the model and the store, which are tested.

- [ ] **Step 1: Keep Kokoro voices out of the language sections**

In `Sources/Aloud/VoicePopover.swift`, add `import Kokoro`, and in `load()` change:

```swift
        let voices = model.provider.voices
        groups = VoiceGroups.group(voices, currentLanguage: VoiceGroups.currentLanguage)
        recommended = RecommendedVoices.resolve(voices)
```

to:

```swift
        // Kokoro voices have their own section above; the language sections are the
        // rest.
        let voices = model.provider.voices.filter { !KokoroCatalogue.isKokoro($0.id) }
        groups = VoiceGroups.group(voices, currentLanguage: VoiceGroups.currentLanguage)
        recommended = RecommendedVoices.resolve(voices)
```

- [ ] **Step 2: Add the section**

Add after `recommendedSection`:

```swift
    /// The Kokoro voices, when the app has the engine: the header carries the caption,
    /// the download or the failure, and the rows are the catalogue by region. Before the
    /// download every row is a download row; during it they are dimmed; after it they
    /// are voices like any other, and the picked one spins while its models load. A
    /// search shows the section only when a Kokoro voice matches.
    @ViewBuilder private var kokoroSection: some View {
        if let kokoro = model.kokoro, let store = model.kokoroStore {
            let installed = store.isInstalledNow
            let matching = VoiceSearch.filter(
                [VoiceGroup(language: "kokoro", name: Copy.kokoroSection, voices: KokoroCatalogue.speechVoices)],
                query: query
            ).first?.voices.map(\.id) ?? []
            if !matching.isEmpty {
                Section {
                    ForEach(KokoroCatalogue.regions) { region in
                        ForEach(region.voices.filter { matching.contains($0.id) }) { k in
                            let v = k.voice
                            let picked = v.id == model.player.voice?.id
                            VoiceRow(
                                name: v.name, region: v.regionName, quality: v.quality.label,
                                badge: installed ? nil : store.release.sizeLabel,
                                isSelected: installed && picked,
                                isInstalled: installed,
                                isBusy: installed && picked && kokoro.isWarming,
                                isDimmed: Self.isBusy(store.state),
                                onPreview: { model.player.preview(v) },
                                onPick: {
                                    if installed { model.pickVoice(v) } else { model.downloadKokoro(picking: v) }
                                })
                        }
                    }
                } header: {
                    DownloadBanner(
                        title: Copy.kokoroSection, phase: Self.phase(store.state),
                        onCancel: { model.cancelKokoroDownload() },
                        onRetry: { model.downloadKokoro(picking: model.pendingKokoroPick) })
                }
            }
        }
    }

    static func phase(_ state: KokoroStoreState) -> DownloadBanner.Phase {
        switch state {
        case .absent: .idle(Copy.kokoroCaption)
        case .downloading(let f): .progress(f)
        case .installing: .busy(Copy.kokoroInstalling)
        case .installed: .idle("")
        case .failed(let message): .failed(message)
        }
    }

    static func isBusy(_ state: KokoroStoreState) -> Bool {
        switch state {
        case .downloading, .installing: true
        default: false
        }
    }
```

`DownloadBanner`'s `.idle("")` draws an empty caption line under the installed section's title; change the banner's `.idle` case to skip the `Text` when the caption is empty:

```swift
            case .idle(let caption):
                if !caption.isEmpty {
                    Text(caption)
                        .font(Type.caption)
                        .foregroundStyle(Ink.soft)
                        .fixedSize(horizontal: false, vertical: true)
                }
```

Place the section first in the `LazyVStack`, above `recommendedSection`:

```swift
                LazyVStack(alignment: .leading, spacing: Space.xs) {
                    kokoroSection
                    recommendedSection
```

- [ ] **Step 3: Build**

```bash
make check 2>&1 | tail -3
make test 2>&1 | grep -E "LiteralLintTests|Test run" | tail -2
```

Expected: clean, and the lint still passes: the section adds no literal sizes.

- [ ] **Step 4: Run the app and look**

```bash
make dev
```

Open the voice picker from the transport bar.
Check, with the bundle absent (remove `~/Library/Application Support/Aloud/Kokoro` first if needed):

- The Kokoro section sits above Recommended with the header `Kokoro` and the caption on one line under it.
- Seven rows, United States then United Kingdom, each with the download arrow, the size badge and `Download` in place of the quality.
- Clicking any row starts the download: the caption becomes a progress bar with Cancel, and the rows dim.
- Cancel returns the section to the caption and the arrows.
- Letting the download finish: `Installing` with a spinner, then the rows become playable and the clicked row is checked; that row shows a spinner in place of the play icon for a few seconds, then the play icon.
- Typing `Fable` in the search shows the Kokoro section with one row and the language sections that match; typing `Zoe` hides the Kokoro section.
- Quitting the app mid-download and relaunching: the picker opens on the progress bar, not on the caption.
- Turning Wi-Fi off mid-download: the header shows `No internet connection.` with Retry, and Retry continues from where it stopped.

Fix anything that looks off before committing, including things that are not this task's: a header that wraps, a badge that misaligns, a spinner that shifts the name.

- [ ] **Step 5: Commit**

```bash
git add Sources/Aloud/VoicePopover.swift Sources/AloudUI/Components/DownloadBanner.swift
git commit -m "The voice picker gains the Kokoro section, with the download in its header"
```

---

### Task 11: Settings, the README, the gated integration test, and the checks by ear

**Files:**
- Modify: `Sources/Aloud/SettingsView.swift:87-119` (the Voice section)
- Modify: `README.md:79` and `:87`
- Create: `Tests/KokoroTests/KokoroIntegrationTests.swift`

- [ ] **Step 1: The Settings row**

In `Sources/Aloud/SettingsView.swift`, add `import Kokoro` and, inside `Section("Voice")` after the `Default speed` picker:

```swift
                if let store = model.kokoroStore {
                    LabeledContent(Copy.kokoroSettingsLabel) {
                        HStack(spacing: Space.m) {
                            Text(Self.kokoroStatus(store.state))
                                .foregroundStyle(Ink.soft)
                            switch store.state {
                            case .installed:
                                Button(Copy.remove) { model.removeKokoro() }
                            case .downloading:
                                Button(Copy.cancel) { model.cancelKokoroDownload() }
                            case .installing:
                                ProgressView().controlSize(.small)
                            case .absent, .failed:
                                Button(Copy.download) { model.downloadKokoro(picking: nil) }
                            }
                        }
                    }
                }
```

and a helper after `pauseBinding`:

```swift
    static func kokoroStatus(_ state: KokoroStoreState) -> String {
        switch state {
        case .absent: Copy.kokoroAbsent
        case .downloading(let f): f.formatted(.percent.precision(.fractionLength(0)))
        case .installing: Copy.kokoroInstalling
        case .installed(let version, let bytes): Copy.kokoroInstalled(version: version, size: "\(bytes / 1_000_000) MB")
        case .failed(let message): message
        }
    }
```

`1_000_000` is a divisor in a string helper, not a layout size; the lint patterns do not match it.
If `swift format` or a reviewer objects, add `public static let bytesPerMegabyte = 1_000_000` to `Size` in `Tokens.swift` and use it here and in `KokoroReleaseInfo.sizeLabel`.

- [ ] **Step 2: The README**

In `README.md`, change line 79:

```markdown
- Lets you preview every voice on the Mac before picking one, with seven recommended voices at the top of the list.
```

to:

```markdown
- Lets you preview every voice on the Mac before picking one, with seven recommended voices at the top of the list.
- Adds seven Kokoro voices, neural voices Apple does not ship, as a one-time download from Aloud's own releases that then runs entirely on your Mac.
```

and line 87:

```markdown
Aloud has no account, sends nothing off your Mac, and costs nothing.
```

to:

```markdown
Aloud has no account, sends nothing off your Mac, and costs nothing.
The one thing it ever downloads is the Kokoro voice models, once, from Aloud's own GitHub release, and only when you pick one of those voices.
```

- [ ] **Step 3: The gated integration test**

Create `Tests/KokoroTests/KokoroIntegrationTests.swift`:

```swift
import Foundation
import Testing

@testable import Kokoro

/// Runs only when `ALOUD_KOKORO_BUNDLE` names a folder holding the real bundle (the
/// manifest at its root), for example `.build/kokoro-bundle/kokoro-1` after
/// `make kokoro-bundle`. It loads the real engine and speaks one sentence.
@Suite struct KokoroIntegrationTests {
    static var bundle: URL? {
        ProcessInfo.processInfo.environment["ALOUD_KOKORO_BUNDLE"].map { URL(fileURLWithPath: $0) }
    }

    @Test(.enabled(if: KokoroIntegrationTests.bundle != nil))
    func theRealEngineSpeaksASentence() async throws {
        let root = try #require(Self.bundle)
        let cache = FileManager.default.temporaryDirectory.appendingPathComponent("kokoro-cache-\(UUID().uuidString)")
        let engine = KokoroEngine()
        try await engine.load(root: root, cache: cache)
        for voice in ["af_bella", "bm_fable"] {
            let samples = try await engine.synthesize("Nobody really teaches you research.", voice: voice, speed: 1)
            let seconds = Double(samples.count) / KokoroPlayback.sampleRate
            #expect(seconds > 1 && seconds < 5, voice)
            #expect(samples.allSatisfy(\.isFinite), voice)
            #expect(samples.contains { abs($0) > 0.01 }, voice)
        }
        await #expect(throws: KokoroEngineError.nothingToSay) {
            _ = try await engine.synthesize("***", voice: "af_bella", speed: 1)
        }
        try? FileManager.default.removeItem(at: cache)
    }
}
```

Run it once with the bundle plan 2 built:

```bash
ALOUD_KOKORO_BUNDLE=$PWD/.build/kokoro-bundle/kokoro-1 swift test --filter KokoroIntegrationTests 2>&1 | grep -E "Test .* (passed|failed|skipped)|error:" | tail -3
```

Expected: one pass, after the tens of seconds the first compile takes.
Without the variable it is skipped.
If `***` synthesizes to a short silence rather than throwing, the SDK's inaudible check did not fire: drop the last expectation and note it in the commit message.

- [ ] **Step 4: The whole suite, the lint, and the packaged app**

```bash
make check 2>&1 | tail -3
make test 2>&1 | grep -E "Test run" | tail -1
```

Then the resource bundles in the packaged app, which is where a static MisakiSwift can lose its data folder:

```bash
which xcodegen xcodebuild && xcodegen generate >/dev/null && xcodebuild -project Aloud.xcodeproj -scheme Aloud -configuration Debug -derivedDataPath .build/xcode build 2>&1 | tail -2
ls .build/xcode/Build/Products/Debug/Aloud.app/Contents/Resources | grep -i "bundle"
```

Expected: `MisakiSwift_MisakiSwift.bundle` and `kokoro-coreml_KokoroTTS.bundle` in `Contents/Resources`.
If `xcodegen` or `xcodebuild` is not on the machine, say so in the report; the `make dev` build finds the bundles through the build folder and is enough for the checks by ear.

- [ ] **Step 5: The checks by ear**

With `make dev` and the bundle installed, listen for:

- Each of the seven voices at 1x, 2x and 3x, on a paragraph of a real document. If 3x is audibly garbled where 2x is not, that is the finding the spec anticipates: record it, and cap the model's speed at 2 with an `AVAudioUnitTimePitch` on the playback engine covering the rest, as a follow-up task.
- The gap between sentences with prefetch on: it should be the configured pause and nothing more.
- A preview started while a document is playing: the sentence stops, the preview plays, and Play resumes the sentence.
- Stop mid-sentence: silence at once, and Play starts the same sentence again.
- Rate and volume changes mid-sentence: the sentence starts again from its beginning at the new rate or volume.
- Unplugging headphones mid-sentence: playback pauses with the existing notice, and Play speaks again through the speakers.
- Removing the model from Settings while a Kokoro voice is picked: the reading continues in the system voice with the existing notice.
- Play in a Kokoro voice from cold: the first sentence starts within about half a second once the picked row's spinner has gone.

Fix what is off, including anything unrelated that looks wrong on the way.

- [ ] **Step 6: Commit**

```bash
make check 2>&1 | tail -3
git add Sources/Aloud/SettingsView.swift README.md Tests/KokoroTests/KokoroIntegrationTests.swift
git commit -m "Settings shows the Kokoro model, the README says what is downloaded, and the real engine has a gated test"
```

---

## Self-review against the spec

- "The voice picker gains a section at the top, above Recommended, headed Kokoro, with a one-line caption": Task 10, with the caption in `Copy.kokoroCaption`.
- "Grouped by region, each in the same VoiceRow": Task 10 over `KokoroCatalogue.regions` from Task 3.
- "Before the download, every row shows the download arrow and the size badge. Clicking any row starts the one download": Task 10's `isInstalled: false` rows and `downloadKokoro(picking:)` from Task 9.
- "During the download, the section header shows a progress bar with a Cancel button and the rows are dimmed": `DownloadBanner.progress` and `isDimmed` from Task 8.
- "When the download finishes, the rows become playable and the row that was clicked is picked": `pendingKokoroPick` and `store.onInstalled` in Task 9.
- "On the first pick after an install, the picked row shows a spinner while the models compile and load": `isBusy` bound to `kokoro.isWarming` in Task 10.
- "If the download or install fails, the header shows the error in one sentence with a Retry button": `DownloadBanner.failed` and the store's three sentences in Task 4.
- "Search finds Kokoro voices like any other": Task 10 filters the catalogue through `VoiceSearch`.
- "Settings gains a row under the Voice picker": Task 11.
- "The first sentence begins within about half a second": `prepare` in Task 1 and the one-slot cache in Task 7; warm on pick in Task 9.
- "A rate or volume change mid-sentence re-speaks that sentence from its start": the player already re-speaks the tail from the current word; with no word callbacks `currentWordStart` is nil and the tail is the whole sentence, which is the spec's behaviour with no change.
- "If the model is removed while a Kokoro voice is picked, the player falls back to the system voice with the notice": `removeKokoro` in Task 9.
- "The README gains one sentence under the voices bullet and one under the line that says Aloud sends nothing off your Mac": Task 11.
- Packages: plan 1. `Kokoro` module and its five types: Tasks 3 to 7. `Speech` changes: Tasks 1 and 2. `Aloud` changes: Tasks 9 to 11. Entitlement: Task 3.
- Error handling: download and install failures in Task 4; load failure in Tasks 7 and 9; a sentence that phonemizes to nothing in Task 7; crash mid-install and quit mid-download in Task 4's `start`.
- Testing: `KokoroTests` cover the catalogue, the store and the provider as the spec lists; `SpeechTests` cover the composite and the player's prepare; the gated integration test is Task 11.
- Placeholder scan: `KokoroRelease` carries two values that exist only once plan 2 has run, and the plan says exactly where to read them; the caption's number is the spec's and is corrected from the same source. Nothing else is deferred.
- Type consistency: `KokoroStore.isInstalledNow`, `installedRoot`, `compiledCache`, `release`, `paths`, `onInstalled`, `start()`, `download()`, `cancel()`, `remove()` are used by Tasks 7, 9 and 10 under those names; `KokoroVoiceProvider.warm()`, `unload()`, `isWarming`, `isLoaded`, `onLoadFailure`, `store` likewise; `DownloadBanner.Phase` cases `idle`, `progress`, `busy`, `failed` match Task 10's `phase(_:)`; `VoiceRow(isBusy:isDimmed:)` match between Tasks 8 and 10; `Player.revalidateVoice()` from Task 1 is called in Task 9; `FakeVoiceProvider(voices:)` from Task 1 is used in Task 2.
