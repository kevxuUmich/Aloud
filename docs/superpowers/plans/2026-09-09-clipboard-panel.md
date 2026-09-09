# Clipboard Panel Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** The global hotkey opens a small floating panel under the menu bar that previews the clipboard and offers to play it, writing nothing until Play; and the system's Now Playing card gains a subtitle and artwork.

**Architecture:** The preview is a value in `Vault` (`ClipboardPreview`), the panel's state is an enum on `AppModel` driven by three model methods, and the panel itself is an AppKit `NSPanel` hosting a SwiftUI view.
The panel's drawing is a pure `AloudUI` component (`ClipboardCard`) that the gallery shows in every state; the app binds it to the model in `ClipboardPanelView`.
`NowPlaying` in `Speech` grows a subtitle and artwork, mapped to the MediaPlayer keys in `SystemNowPlayingCenter`.

**Tech Stack:** Swift 6.2 strict concurrency, SwiftUI and AppKit on macOS 26 (Liquid Glass), Swift Testing, MediaPlayer, `sindresorhus/KeyboardShortcuts` 1.15.0.

**Spec:** `docs/superpowers/specs/2026-09-09-clipboard-panel-design.md`

Branch: `clipboard-panel`, which already carries the spec.

## Global Constraints

- macOS 26 only; Swift 6 language mode with strict concurrency in every target.
- No number, colour, font size or duration literal in `Sources/Aloud` or `Sources/AloudUI` outside `Sources/AloudUI/Tokens.swift`. `Tests/AloudUITests/LiteralLintTests.swift` enforces the common forms; also avoid bare numeric `let`s in views.
- Duration estimate is `Prose.Estimate`: 160 words per minute at rate 1.0.
- One `Player`, shared by the window, the menu-bar item and now the panel.
- Accessibility: icon-only buttons carry `accessibilityLabel`; decorative images are `accessibilityHidden(true)`.
- Every commit passes `make check` and `make test`. No em dash in any file (plain dash). One sentence per line in Markdown. No co-author line in commits.
- Commit messages follow the repo's form: a lower-case area prefix and a sentence, for example `vault: a clipboard preview is the note before it is a file`.
- Panel copy is exactly the spec's: `From clipboard · ~3 min · 412 words`, `Nothing to read`, `The clipboard has no text`, `Pick a folder in Aloud first`.
- `swift format lint --strict` runs in `make check`; run `swift format --in-place --recursive Sources Tests` before committing if lint complains.

## One deviation from the spec, decided here

The spec says the panel "does not take focus" and also that Enter, Space and Escape reach it.
A local event monitor only sees events delivered to Aloud, and with Safari in front every keystroke goes to Safari.
So the panel is a `.nonactivatingPanel` that is made key with `makeKeyAndOrderFront`: Aloud stays inactive and Safari stays the active app, but keystrokes reach the panel while it is up, which is how Spotlight and Alfred behave.
When the panel resigns key, for a click anywhere else, it dismisses, which is the spec's "a click anywhere outside dismisses" without a global mouse monitor.

## One bug fixed on the way

`pasteNote(text:andPlay:)` calls `open(doc)` and then `player.play()` at once, but `open` extracts in a `Task`, so `play()` runs before the load: on an empty player it is a no-op and the note never starts, and with another document loaded it plays that one for a moment.
Task 4 makes `open` return its task and awaits it before playing, for the hotkey and the window's Cmd+Shift+V alike.

---

## File structure

```
Sources/
  Vault/
    ClipboardPreview.swift                (create) text, title, words, estimate(factor:)
  Speech/
    NowPlaying.swift                      (modify) subtitle and artwork in update and push; artist and artwork keys
  AloudUI/
    Tokens.swift                          (modify) Size.clipboardPanelWidth, Size.clipboardPlate, Motion.emptyPanelHold, Type.panelTitle, Type.panelSubtitle
    Components/ClipboardCard.swift        (create) the panel's drawing, model-free
    Gallery.swift                         (modify) the card in its four states
  Aloud/
    ClipboardPanelState.swift             (create) the enum
    AppModel.swift                        (modify) clipboardPanel, preview(clipboard:), previewClipboard(), playPreview(), dismissClipboardPanel(); open returns its task; subtitle for Now Playing; shakeCount removed
    ClipboardPanelView.swift              (create) ClipboardCard bound to the model
    ClipboardPanelController.swift        (create) the NSPanel, its placement, its keys
    NowPlayingArtwork.swift               (create) the waveform on the accent colour, rendered once
    AloudApp.swift                        (modify) the controller; the wiggle removed
Tests/
  VaultTests/ClipboardPreviewTests.swift  (create)
  SpeechTests/NowPlayingTests.swift       (modify) subtitle and artwork reach the centre
  AloudTests/AppModelTests.swift          (modify) the panel's state machine
  AloudUITests/GalleryTests.swift         (unchanged; the gallery test builds every section)
```

---

### Task 1: `ClipboardPreview` in `Vault`

**Files:**
- Create: `Sources/Vault/ClipboardPreview.swift`
- Test: `Tests/VaultTests/ClipboardPreviewTests.swift`

**Interfaces:**
- Consumes: `Title.from(text:fallback:)` in `Sources/Vault/Title.swift`, `Estimate.words(in:)` and `Estimate.duration(words:factor:)` in `Sources/Prose/Estimate.swift`.
- Produces: `public struct ClipboardPreview: Equatable, Sendable { let text: String; let title: String; let words: Int; init?(text: String); func estimate(factor: Double) -> Duration }`.

- [ ] **Step 1: Write the failing tests**

`Tests/VaultTests/ClipboardPreviewTests.swift`:

```swift
import Testing

@testable import Vault

@Suite struct ClipboardPreviewTests {
    @Test func trimsTheTextAndTakesTheTitleFromTheFirstLine() {
        let p = ClipboardPreview(text: "  \n# Fast year\n\nOne two three.\n  ")
        #expect(p?.text == "# Fast year\n\nOne two three.")
        #expect(p?.title == "Fast year")
    }
    @Test func isNilForWhitespace() {
        #expect(ClipboardPreview(text: " \n\t ") == nil)
        #expect(ClipboardPreview(text: "") == nil)
    }
    @Test func countsWordsAndEstimatesAtTheRate() {
        let p = ClipboardPreview(text: String(repeating: "word ", count: 320))!
        #expect(p.words == 320)
        #expect(p.estimate(factor: 1) == .seconds(120))
        #expect(p.estimate(factor: 2) == .seconds(60))
    }
    @Test func titleFallsBackToNoteWhenTheFirstLineIsOnlyHashes() {
        // `Title.from` clips a heading of nothing to an empty string, and the panel
        // must still have a title to show, the same one the file would be named.
        let p = ClipboardPreview(text: "#\n")
        #expect(p?.title == "Note")
    }
}
```

- [ ] **Step 2: Run them to verify they fail**

Run: `make test 2>&1 | grep -E "ClipboardPreview|error:" | head`
Expected: compile error, `cannot find 'ClipboardPreview' in scope`.

- [ ] **Step 3: Write the implementation**

`Sources/Vault/ClipboardPreview.swift`:

```swift
import Foundation
import Prose

/// The clipboard as a note would take it, before it is a file: what the panel shows
/// and what `Vault.makeNote` will write if Play is pressed. Title, words and the
/// estimate are the library's own rules, so the panel can never disagree with the
/// card the note gets once it is written.
public struct ClipboardPreview: Equatable, Sendable {
    public let text: String
    public let title: String
    public let words: Int

    /// Nil when there is nothing there once the whitespace is trimmed, which is what
    /// the hotkey has to know first.
    public init?(text: String) {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }
        self.text = trimmed
        // The fallback is the file's own fallback: `NoteName.make` names an untitled
        // note "Note", so the panel says the same.
        let t = Title.from(text: trimmed, fallback: "Note")
        self.title = t.isEmpty ? "Note" : t
        self.words = Estimate.words(in: trimmed)
    }

    public func estimate(factor: Double) -> Duration {
        Estimate.duration(words: words, factor: factor)
    }
}
```

- [ ] **Step 4: Run the tests to verify they pass**

Run: `make test 2>&1 | grep -E "ClipboardPreview|passed|failed" | head`
Expected: the four `ClipboardPreviewTests` pass; the suite summary reads all passed.

- [ ] **Step 5: Commit**

```bash
make check
git add Sources/Vault/ClipboardPreview.swift Tests/VaultTests/ClipboardPreviewTests.swift
git commit -m "vault: a clipboard preview is the note before it is a file"
```

---

### Task 2: Now Playing carries a subtitle and artwork

**Files:**
- Modify: `Sources/Speech/NowPlaying.swift`
- Test: `Tests/SpeechTests/NowPlayingTests.swift`

**Interfaces:**
- Produces: `NowPlaying.init(player:artwork:center:commands:)` where `artwork: NSImage? = nil`; `NowPlaying.update(title:subtitle:)`; `SystemNowPlayingCenter` reads the info keys `"subtitle"` (String) and `"artwork"` (NSImage).
- Every caller of `update(title:)` in `Sources/Aloud/AppModel.swift` changes in Task 4; until then the old signature is kept as a one-line overload so the app still builds.

- [ ] **Step 1: Write the failing test**

Add to `Tests/SpeechTests/NowPlayingTests.swift`, inside the suite after `mirrorsTitleAndStateAndAnswersCommands`:

```swift
    /// The card has a subtitle line and a plate, and both are the app's to fill.
    @Test func pushesTheSubtitleAndTheArtwork() {
        let p = Player(provider: FakeVoiceProvider())
        let center = FakeCenter()
        let art = NSImage(size: NSSize(width: 1, height: 1))
        let np = NowPlaying(player: p, artwork: art, center: center, commands: FakeCommands())
        np.update(title: "Essay", subtitle: "Essays")
        #expect(center.info["title"] as? String == "Essay")
        #expect(center.info["subtitle"] as? String == "Essays")
        #expect(center.info["artwork"] as? NSImage === art)
        np.update(title: nil, subtitle: nil)
        #expect(center.info["title"] as? String == "Aloud")
        #expect(center.info["subtitle"] == nil)
    }
```

Add `import AppKit` at the top of the test file.

- [ ] **Step 2: Run it to verify it fails**

Run: `make test 2>&1 | grep -E "NowPlaying|error:" | head`
Expected: compile error, `extra argument 'artwork' in call`.

- [ ] **Step 3: Write the implementation**

In `Sources/Speech/NowPlaying.swift`:

Add `import AppKit` under `import Foundation`.

Replace `SystemNowPlayingCenter.set(info:)` with:

```swift
    public func set(info: [String: Any]) {
        var mp: [String: Any] = [:]
        if let t = info["title"] { mp[MPMediaItemPropertyTitle] = t }
        if let s = info["subtitle"] { mp[MPMediaItemPropertyArtist] = s }
        if let d = info["duration"] { mp[MPMediaItemPropertyPlaybackDuration] = d }
        if let e = info["elapsed"] { mp[MPNowPlayingInfoPropertyElapsedPlaybackTime] = e }
        if let r = info["rate"] { mp[MPNowPlayingInfoPropertyPlaybackRate] = r }
        if let image = info["artwork"] as? NSImage {
            // The card asks for the size it wants and gets the one image whatever it asks.
            mp[MPMediaItemPropertyArtwork] = MPMediaItemArtwork(boundsSize: image.size) { _ in image }
        }
        MPNowPlayingInfoCenter.default().nowPlayingInfo = mp
    }
```

In `NowPlaying`, add stored properties and change the init and `update`:

```swift
    private let player: Player
    private let center: any NowPlayingCenter
    /// One image for every document: the app renders it once at launch, and the card
    /// shows a plate rather than a grey square.
    private let artwork: NSImage?
    private var title: String?
    private var subtitle: String?
    private var observation: Task<Void, Never>?

    public init(
        player: Player, artwork: NSImage? = nil, center: any NowPlayingCenter = SystemNowPlayingCenter(),
        commands: any RemoteCommands = SystemRemoteCommands()
    ) {
        self.player = player
        self.artwork = artwork
        self.center = center
        // ... the commands.bind call and observe() stay exactly as they are ...
    }

    public func update(title: String?, subtitle: String?) {
        self.title = title
        self.subtitle = subtitle
        push()
    }
```

And in `push()`, build the dictionary with the two optional keys:

```swift
    private func push() {
        var info: [String: Any] = [
            "title": title ?? "Aloud",
            "duration": player.timeline.total.seconds,
            "elapsed": player.elapsed.seconds,
            "rate": player.isPlaying ? player.rate.factor : 0,
        ]
        if let subtitle { info["subtitle"] = subtitle }
        if let artwork { info["artwork"] = artwork }
        center.set(info: info)
        center.set(playing: player.isPlaying)
    }
```

Keep the app building until Task 4 by adding, under the new `update`:

```swift
    /// Kept for the app until every caller passes a subtitle; removed in the same
    /// change that makes them.
    public func update(title: String?) { update(title: title, subtitle: nil) }
```

Also update the existing test `mirrorsTitleAndStateAndAnswersCommands` and `aLoadPushesTheNewDuration` to call `np.update(title: "Essay", subtitle: nil)`.

- [ ] **Step 4: Run the tests to verify they pass**

Run: `make test 2>&1 | grep -E "NowPlaying|passed|failed" | head`
Expected: all four `NowPlayingTests` pass.

- [ ] **Step 5: Commit**

```bash
make check
git add Sources/Speech/NowPlaying.swift Tests/SpeechTests/NowPlayingTests.swift
git commit -m "speech: the Now Playing card carries a subtitle and artwork"
```

---

### Task 3: Tokens and the model-free `ClipboardCard`, in the gallery

**Files:**
- Modify: `Sources/AloudUI/Tokens.swift`
- Create: `Sources/AloudUI/Components/ClipboardCard.swift`
- Modify: `Sources/AloudUI/Gallery.swift`
- Test: `Tests/AloudUITests/GalleryTests.swift` (already builds the whole gallery) and `Tests/AloudUITests/LiteralLintTests.swift` (already scans every file).

**Interfaces:**
- Produces:

```swift
public struct ClipboardCard: View {
    public enum Transport { case disabled, ready, playing(isPlaying: Bool) }
    public init(
        title: String, subtitle: String, transport: Transport,
        progress: Double, elapsed: String, remaining: String, skipSeconds: Int,
        onPlay: @escaping () -> Void, onBack: @escaping () -> Void, onForward: @escaping () -> Void,
        onSeek: @escaping (Double) -> Void)
}
```

`.disabled` is the empty clipboard and the missing folder: the play button is drawn but inert.
`.ready` is before Play: Play alone enabled, scrubber empty.
`.playing(isPlaying:)` is the mini player: every control live, the play button a pause when `isPlaying`.

- [ ] **Step 1: Add the tokens**

In `Sources/AloudUI/Tokens.swift`, add to `Size` after `settingsWidth`:

```swift
    /// The clipboard panel under the menu bar, and the square glyph plate at its left:
    /// the Now Playing card's own proportions, so the two read as the same thing.
    public static let clipboardPanelWidth: CGFloat = 360
    public static let clipboardPlate: CGFloat = 88
    /// The waveform inside the plate.
    public static let clipboardGlyph: CGFloat = 40
```

To `Type` after `singleLine`:

```swift
    /// The clipboard panel's two lines, the card's title and its subtitle.
    public static let panelTitle = Font.headline
    public static let panelSubtitle = Font.subheadline
```

To `Motion` after `dimmed`:

```swift
    /// How long the panel stays when the clipboard has no text: long enough to read
    /// two short lines, not long enough to reach for the mouse.
    public static let emptyPanelHold: Double = 1.6
```

To `Radius` after `dockedTop`:

```swift
    /// The glyph plate in the clipboard panel.
    public static let plate: CGFloat = m
```

To `Ink` after `landingGlyph`:

```swift
    /// The clipboard panel's plate: the accent, with the waveform in white on it.
    public static let plate = Color.accentColor
    public static let plateGlyph = Color.white
```

- [ ] **Step 2: Write the card**

`Sources/AloudUI/Components/ClipboardCard.swift`:

```swift
import SwiftUI

/// The clipboard panel's drawing, laid out like the system's Now Playing card: a
/// square glyph plate at the left, the title and a subtitle at the right, the
/// transport under them and the scrubber under that. It knows nothing about the
/// player; the app hands it strings and closures, so the gallery can show every state.
public struct ClipboardCard: View {
    public enum Transport: Equatable {
        /// Nothing to play: the empty clipboard, or no folder to write into.
        case disabled
        /// Before Play: Play alone is live and the scrubber is empty.
        case ready
        /// After Play: the mini player, bound to the one player.
        case playing(isPlaying: Bool)
    }
    let title: String
    let subtitle: String
    let transport: Transport
    let progress: Double
    let elapsed: String
    let remaining: String
    let skipSeconds: Int
    let onPlay: () -> Void
    let onBack: () -> Void
    let onForward: () -> Void
    let onSeek: (Double) -> Void

    public init(
        title: String, subtitle: String, transport: Transport,
        progress: Double, elapsed: String, remaining: String,
        skipSeconds: Int = TransportButton.defaultSkipSeconds,
        onPlay: @escaping () -> Void, onBack: @escaping () -> Void, onForward: @escaping () -> Void,
        onSeek: @escaping (Double) -> Void
    ) {
        self.title = title
        self.subtitle = subtitle
        self.transport = transport
        self.progress = progress
        self.elapsed = elapsed
        self.remaining = remaining
        self.skipSeconds = skipSeconds
        self.onPlay = onPlay
        self.onBack = onBack
        self.onForward = onForward
        self.onSeek = onSeek
    }

    var isPlayer: Bool {
        if case .playing = transport { return true }
        return false
    }
    var showsPause: Bool {
        if case .playing(let isPlaying) = transport { return isPlaying }
        return false
    }

    public var body: some View {
        GlassBar {
            VStack(spacing: Space.m) {
                HStack(alignment: .top, spacing: Space.l) {
                    plate
                    VStack(alignment: .leading, spacing: Space.xs) {
                        Text(title).font(Type.panelTitle).lineLimit(Type.cardTitleLines)
                        Text(subtitle).font(Type.panelSubtitle).foregroundStyle(Ink.soft)
                            .lineLimit(Type.singleLine)
                        Spacer(minLength: Space.none)
                        HStack(spacing: Space.xl) {
                            TransportButton(.back15, skipSeconds: skipSeconds, action: onBack)
                                .disabled(!isPlayer)
                            TransportButton(showsPause ? .pause : .play, action: onPlay)
                                .disabled(transport == .disabled)
                            TransportButton(.forward15, skipSeconds: skipSeconds, action: onForward)
                                .disabled(!isPlayer)
                        }
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                }
                Scrubber(progress: progress, elapsed: elapsed, remaining: remaining, onSeek: onSeek)
                    .disabled(!isPlayer)
            }
        }
        .frame(width: Size.clipboardPanelWidth)
    }

    var plate: some View {
        RoundedRectangle(cornerRadius: Radius.plate, style: .continuous)
            .fill(Ink.plate)
            .frame(width: Size.clipboardPlate, height: Size.clipboardPlate)
            .overlay {
                Image(systemName: "waveform")
                    .resizable().scaledToFit()
                    .frame(width: Size.clipboardGlyph, height: Size.clipboardGlyph)
                    .foregroundStyle(Ink.plateGlyph)
            }
            .accessibilityHidden(true)
    }
}
```

- [ ] **Step 3: Add the four states to the gallery**

In `Sources/AloudUI/Gallery.swift`, append `"ClipboardCard"` to `sections`, and add after the `VoiceRow` section:

```swift
                section("ClipboardCard") {
                    VStack(alignment: .leading, spacing: Space.l) {
                        ClipboardCard(
                            title: "It's been a fast year.", subtitle: "From clipboard · ~3 min · 412 words",
                            transport: .ready, progress: 0, elapsed: "0:00", remaining: "~2:35",
                            onPlay: {}, onBack: {}, onForward: {}, onSeek: { _ in })
                        ClipboardCard(
                            title: "It's been a fast year.", subtitle: "From clipboard · ~3 min · 412 words",
                            transport: .playing(isPlaying: true), progress: 0.3, elapsed: "0:46",
                            remaining: "~1:49", onPlay: {}, onBack: {}, onForward: {}, onSeek: { _ in })
                        ClipboardCard(
                            title: "Nothing to read", subtitle: "The clipboard has no text",
                            transport: .disabled, progress: 0, elapsed: "0:00", remaining: "~0:00",
                            onPlay: {}, onBack: {}, onForward: {}, onSeek: { _ in })
                        ClipboardCard(
                            title: "It's been a fast year.", subtitle: "Pick a folder in Aloud first",
                            transport: .ready, progress: 0, elapsed: "0:00", remaining: "~2:35",
                            onPlay: {}, onBack: {}, onForward: {}, onSeek: { _ in })
                    }
                }
```

The gallery's `progress: 0.3` is a literal in a gallery, the same as the existing `progress: 0.07`; the lint patterns do not match `progress:`.

- [ ] **Step 4: Run the tests and the lint**

Run: `make test 2>&1 | grep -E "Gallery|LiteralLint|passed|failed" | head`
Expected: `galleryBuilds` and `noLiteralsOutsideTokens` pass.

- [ ] **Step 5: Look at it**

Run: `make gallery`
Expected: the gallery window opens with the four cards at the bottom.
Check that the plate is square, the title and subtitle sit at the top right, the transport under them, the scrubber the full width beneath.
If the transport row wraps or the card is taller than the plate by more than a control, adjust spacing tokens used, never literals.

- [ ] **Step 6: Commit**

```bash
make check
git add Sources/AloudUI/Tokens.swift Sources/AloudUI/Components/ClipboardCard.swift Sources/AloudUI/Gallery.swift
git commit -m "ui: the clipboard card, laid out like the Now Playing card, in the gallery"
```

---

### Task 4: The panel's state machine on `AppModel`

**Files:**
- Create: `Sources/Aloud/ClipboardPanelState.swift`
- Modify: `Sources/Aloud/AppModel.swift`
- Modify: `Sources/Aloud/AloudApp.swift` (only the `.symbolEffect(.wiggle, value: model.shakeCount)` line, which no longer compiles)
- Modify: `Sources/Speech/NowPlaying.swift` (remove the one-argument `update` overload)
- Test: `Tests/AloudTests/AppModelTests.swift`

**Interfaces:**
- Consumes: `ClipboardPreview` from Task 1, `NowPlaying.update(title:subtitle:)` from Task 2, `Motion.emptyPanelHold` from Task 3.
- Produces on `AppModel`:
  - `var clipboardPanel: ClipboardPanelState?`
  - `func preview(clipboard text: String?)` sets the state from text already read.
  - `func previewClipboard()` reads `NSPasteboard.general` once and calls `preview(clipboard:)`. The hotkey calls this.
  - `@discardableResult func playPreview() -> Task<Void, Never>?` writes the note and moves to `.playing`. Nil when there is nothing to play.
  - `func dismissClipboardPanel()` sets the state to nil.
  - `@discardableResult func open(_ doc: Document, subtitle: String? = nil) -> Task<Void, Never>` where nil means "the folder's name".
  - `init(provider:progress:rootStore:emptyPanelHold:)` with `emptyPanelHold: Duration = .seconds(Motion.emptyPanelHold)`.
- Removes `shakeCount` and `pasteAndPlay()`.

- [ ] **Step 1: Write the state enum**

`Sources/Aloud/ClipboardPanelState.swift`:

```swift
import Vault

/// What the clipboard panel is showing. Nil on the model means no panel.
enum ClipboardPanelState: Equatable {
    /// The clipboard has no text. The panel says so and goes away by itself.
    case empty
    /// The text, before Play. `failure` is a write that did not land, shown in the
    /// subtitle's place so Play can be tried again.
    case preview(ClipboardPreview, failure: String? = nil)
    /// The text, but nowhere to write it. Play opens the window instead.
    case needsFolder(ClipboardPreview)
    /// The note is written and the panel is a mini player for it.
    case playing(ClipboardPreview)

    var preview: ClipboardPreview? {
        switch self {
        case .empty: nil
        case .preview(let p, _), .needsFolder(let p), .playing(let p): p
        }
    }
}
```

- [ ] **Step 2: Write the failing tests**

Add to `Tests/AloudTests/AppModelTests.swift`, inside the suite. `withModel` gains an `emptyPanelHold` parameter; change its signature and the model construction:

```swift
    func withModel(
        emptyPanelHold: Duration = .seconds(1),
        _ body: (AppModel, URL) async throws -> Void
    ) async throws {
        // ... unchanged up to the model ...
        let model = AppModel(
            provider: FakeVoiceProvider(),
            progress: ProgressStore(file: dir.appendingPathComponent("progress.json")),
            rootStore: RootStore(defaults: suite), emptyPanelHold: emptyPanelHold)
        try await body(model, dir)
    }
```

Then the cases:

```swift
    // MARK: The clipboard panel

    /// The hotkey with text: a preview, and nothing on disk until Play.
    @Test func theHotkeyWithTextPreviewsAndWritesNothing() async throws {
        try await withModel { model, dir in
            model.addRoot(dir)
            model.preview(clipboard: "  # Fast year\n\nOne two three.  ")
            let p = ClipboardPreview(text: "# Fast year\n\nOne two three.")!
            #expect(model.clipboardPanel == .preview(p))
            #expect(try FileManager.default.contentsOfDirectory(atPath: dir.path).isEmpty)
        }
    }

    /// An empty clipboard: the panel reports it, then takes itself down.
    @Test func anEmptyClipboardIsReportedThenGoes() async throws {
        try await withModel(emptyPanelHold: .milliseconds(50)) { model, dir in
            model.preview(clipboard: " \n")
            #expect(model.clipboardPanel == .empty)
            try await poll { model.clipboardPanel == nil }
            #expect(model.clipboardPanel == nil)
        }
    }

    /// The empty hold only takes down the empty state: text arriving inside the hold
    /// is a preview that stays.
    @Test func textArrivingDuringTheEmptyHoldStays() async throws {
        try await withModel(emptyPanelHold: .milliseconds(50)) { model, dir in
            model.addRoot(dir)
            model.preview(clipboard: nil)
            model.preview(clipboard: "Hello there.")
            try await Task.sleep(for: .milliseconds(100))
            #expect(model.clipboardPanel == .preview(ClipboardPreview(text: "Hello there.")!))
        }
    }

    /// No folder to write into: the panel says so, and Play has nowhere to go.
    @Test func withNoFolderThePanelAsksForOne() async throws {
        try await withModel { model, _ in
            model.preview(clipboard: "Hello there.")
            #expect(model.clipboardPanel == .needsFolder(ClipboardPreview(text: "Hello there.")!))
            #expect(model.playPreview() == nil)
        }
    }

    /// Play writes exactly one note, opens it, starts it, and the panel becomes a player.
    @Test func playWritesOneNoteAndPlaysIt() async throws {
        try await withModel { model, dir in
            model.addRoot(dir)
            model.preview(clipboard: "Hello there. Two sentences.")
            let play = try #require(model.playPreview())
            await play.value
            let files = try FileManager.default.contentsOfDirectory(atPath: dir.path)
            #expect(files == ["Hello there..md"] || files == ["Hello there.md"])
            #expect(model.current?.title == "Hello there.")
            #expect(model.player.isPlaying)
            #expect(model.clipboardPanel == .playing(ClipboardPreview(text: "Hello there. Two sentences.")!))
        }
    }

    /// A second Play while the first is still writing is one write, not two.
    @Test func aSecondPlayWhileWritingIsIgnored() async throws {
        try await withModel { model, dir in
            model.addRoot(dir)
            model.preview(clipboard: "Hello there.")
            let first = try #require(model.playPreview())
            #expect(model.playPreview() == nil)
            await first.value
            #expect(try FileManager.default.contentsOfDirectory(atPath: dir.path).count == 1)
        }
    }

    /// The hotkey again with different text swaps the preview and leaves the player alone.
    @Test func newTextSwapsThePreviewWithoutStoppingThePlayer() async throws {
        try await withModel { model, dir in
            model.addRoot(dir)
            model.preview(clipboard: "Hello there.")
            await model.playPreview()?.value
            #expect(model.player.isPlaying)
            model.preview(clipboard: "Something else.")
            #expect(model.clipboardPanel == .preview(ClipboardPreview(text: "Something else.")!))
            #expect(model.player.isPlaying)
            #expect(model.current?.title == "Hello there.")
        }
    }

    /// The same text again changes nothing, whether previewing or playing.
    @Test func theSameTextAgainIsANoOp() async throws {
        try await withModel { model, dir in
            model.addRoot(dir)
            model.preview(clipboard: "Hello there.")
            model.preview(clipboard: "Hello there.")
            #expect(model.clipboardPanel == .preview(ClipboardPreview(text: "Hello there.")!))
            await model.playPreview()?.value
            model.preview(clipboard: " Hello there.\n")
            #expect(model.clipboardPanel == .playing(ClipboardPreview(text: "Hello there.")!))
            #expect(model.player.isPlaying)
        }
    }

    /// Dismissing before Play leaves nothing behind; after Play the note stays and so
    /// does the playback.
    @Test func dismissClearsThePanelAndNothingElse() async throws {
        try await withModel { model, dir in
            model.addRoot(dir)
            model.preview(clipboard: "Hello there.")
            model.dismissClipboardPanel()
            #expect(model.clipboardPanel == nil)
            #expect(try FileManager.default.contentsOfDirectory(atPath: dir.path).isEmpty)
            model.preview(clipboard: "Hello there.")
            await model.playPreview()?.value
            model.dismissClipboardPanel()
            #expect(model.clipboardPanel == nil)
            #expect(model.player.isPlaying)
            #expect(try FileManager.default.contentsOfDirectory(atPath: dir.path).count == 1)
        }
    }

    /// A write that fails is reported on the panel, and Play can be pressed again.
    @Test func aFailedWriteIsReportedOnThePanel() async throws {
        try await withModel { model, dir in
            model.addRoot(dir)
            // The folder can be read but not written, so the note cannot land.
            // `setNoteFolder` is not used: it writes the reader's real defaults.
            let fm = FileManager.default
            try fm.setAttributes([.posixPermissions: 0o500], ofItemAtPath: dir.path)
            defer { try? fm.setAttributes([.posixPermissions: 0o700], ofItemAtPath: dir.path) }
            model.preview(clipboard: "Hello there.")
            await model.playPreview()?.value
            guard case .preview(let p, let failure)? = model.clipboardPanel else {
                Issue.record("expected a preview with a failure, got \(String(describing: model.clipboardPanel))")
                return
            }
            #expect(p == ClipboardPreview(text: "Hello there.")!)
            #expect(failure?.hasPrefix("Could not save the note") == true)
            #expect(model.playPreview() != nil)
        }
    }

    /// The window's own paste plays the note it wrote, not the document that was
    /// loaded before it: `play` waits for the load.
    @Test func pasteNoteAndPlayPlaysTheNote() async throws {
        try await withModel { model, dir in
            model.addRoot(dir)
            let a = try document("Alpha one. Alpha two.", named: "a.md", in: dir)
            await model.open(a).value
            #expect(model.current?.id == a.id)
            await model.pasteNote(text: "Beta one.", andPlay: true)?.value
            #expect(model.current?.title == "Beta one.")
            #expect(model.player.script.source == "Beta one.")
            #expect(model.player.isPlaying)
        }
    }
```


- [ ] **Step 3: Run them to verify they fail**

Run: `make test 2>&1 | grep -E "error:" | head`
Expected: compile errors, `value of type 'AppModel' has no member 'preview'` and the rest.

- [ ] **Step 4: Change the model**

In `Sources/Aloud/AppModel.swift`:

Replace the `shakeCount` declaration and its comment with:

```swift
    /// The clipboard panel under the menu bar, or nil when there is none. The hotkey
    /// sets it, the panel's controller shows it, and the three methods below move it.
    var clipboardPanel: ClipboardPanelState?
    /// The write Play started, until it lands. A second Play in that time would be a
    /// second note with the same text.
    private var previewPlay: Task<Void, Never>?
    /// The timer that takes an empty panel down again.
    private var emptyHoldTask: Task<Void, Never>?
    private let emptyPanelHold: Duration
    /// What the Now Playing card says under the title for the document that is open:
    /// the folder's name, or "From clipboard" for a note the panel wrote. Kept so a
    /// reload pushes the same line.
    private var currentSubtitle: String?
```

Change the init signature and body:

```swift
    init(
        provider: any VoiceProvider, progress: ProgressStore = .standard(),
        rootStore: RootStore = RootStore(), emptyPanelHold: Duration = .seconds(Motion.emptyPanelHold)
    ) {
        self.emptyPanelHold = emptyPanelHold
        // ... the rest of the init unchanged ...
```

Replace `pasteAndPlay()`, `clipboardText()` and `installHotkey()` with:

```swift
    /// The hotkey: the clipboard is read once and previewed, and nothing is written
    /// until Play. Read once because a second read a moment later can hand back
    /// something else.
    func previewClipboard() {
        preview(clipboard: NSPasteboard.general.string(forType: .string))
    }

    /// The panel's state from text already in hand, which is what the tests have.
    /// The same text as the panel already shows changes nothing, so a listener who
    /// presses the hotkey twice does not lose the player they started. Different text
    /// swaps the preview and leaves the player alone: the panel is the preview's,
    /// and the transport bar and the menu-bar item still carry the player.
    func preview(clipboard text: String?) {
        emptyHoldTask?.cancel()
        guard let p = text.flatMap(ClipboardPreview.init(text:)) else {
            clipboardPanel = .empty
            emptyHoldTask = Task { [weak self, emptyPanelHold] in
                try? await Task.sleep(for: emptyPanelHold)
                guard !Task.isCancelled, let self, self.clipboardPanel == .empty else { return }
                self.clipboardPanel = nil
            }
            return
        }
        if clipboardPanel?.preview == p { return }
        previewPlay?.cancel()
        previewPlay = nil
        clipboardPanel = noteFolder == nil ? .needsFolder(p) : .preview(p)
    }

    /// The panel's Play: the note is written and opened and starts, and the panel
    /// becomes its player. Nil when there is nothing to play - no preview, no folder,
    /// or a write already in the air. The task is returned so a test can wait for it.
    @discardableResult
    func playPreview() -> Task<Void, Never>? {
        guard case .preview(let p, _)? = clipboardPanel, previewPlay == nil, let folder = noteFolder
        else { return nil }
        let task = Task {
            do {
                try await writeNote(text: p.text, in: folder, andPlay: true)
                guard !Task.isCancelled, clipboardPanel?.preview == p else { return }
                clipboardPanel = .playing(p)
            } catch {
                guard !Task.isCancelled, clipboardPanel?.preview == p else { return }
                clipboardPanel = .preview(p, failure: "Could not save the note: \(error.localizedDescription)")
            }
            previewPlay = nil
        }
        previewPlay = task
        return task
    }

    func dismissClipboardPanel() {
        emptyHoldTask?.cancel()
        clipboardPanel = nil
    }

    /// Registered once, from `start()`, behind its `started` guard.
    private func installHotkey() {
        KeyboardShortcuts.onKeyUp(for: .pasteAndPlay) { [weak self] in
            MainActor.assumeIsolated { self?.previewClipboard() }
        }
    }
```

Replace the two `pasteNote` methods with:

```swift
    /// Clipboard text becomes a note in the default folder and opens ready to play.
    /// The window's Cmd+Shift+V, which writes at once: it is a gesture made inside Aloud.
    func pasteNote(andPlay: Bool = false) {
        guard let p = ClipboardPreview(text: NSPasteboard.general.string(forType: .string) ?? "")
        else {
            notice = "The clipboard has no text"
            return
        }
        pasteNote(text: p.text, andPlay: andPlay)
    }

    /// The same note from text already in hand. The task is returned so a test can
    /// wait for the write and the load; nil when there is no folder to write into.
    @discardableResult
    func pasteNote(text: String, andPlay: Bool = false) -> Task<Void, Never>? {
        guard let folder = noteFolder else {
            notice = "Pick a folder to read from first"
            return nil
        }
        return Task {
            do {
                try await writeNote(text: text, in: folder, andPlay: andPlay)
            } catch {
                notice = "Could not save the note: \(error.localizedDescription)"
            }
        }
    }

    /// The write the panel and the window share. `play` waits for the load: `open`
    /// extracts in a task of its own, and a `play()` before it landed was a no-op on an
    /// empty player and, with another document loaded, a moment of the wrong one.
    private func writeNote(text: String, in folder: URL, andPlay: Bool) async throws {
        let url = try await vault.makeNote(text: text, in: folder)
        await refresh()
        guard let doc = document(at: url) else { return }
        await open(doc, subtitle: "From clipboard").value
        if andPlay, current?.id == doc.id { player.play() }
    }
```

Change `open` to return its task and carry the subtitle. Replace the signature line and the body's `Task {` and the `nowPlaying?.update(title: doc.title)` line:

```swift
    /// `subtitle` is what the Now Playing card says under the title; nil means the
    /// folder the document is in. The task is returned so a caller that needs the load
    /// to have landed, such as a paste that plays, can wait for it.
    @discardableResult
    func open(_ doc: Document, subtitle: String? = nil) -> Task<Void, Never> {
        if doc.id == current?.id {
            if path.last != .reader(doc) { path.append(.reader(doc)) }
            return Task { await followCurrentFile() }
        }
        openGeneration += 1
        let generation = openGeneration
        return Task {
            do {
                let kind = SourceKind(doc.type)
                let script = try await extraction.script(
                    for: doc.url, kind: kind, options: extractOptions)
                guard generation == openGeneration else { return }
                let p = progress.progress(for: doc.url)
                current = doc
                currentSubtitle = subtitle ?? folderName(of: doc)
                player.load(script, at: p?.finished == true ? 0 : (p?.sentenceIndex ?? 0))
                nowPlaying?.update(title: doc.title, subtitle: currentSubtitle)
                if path.last != .reader(doc) { path.append(.reader(doc)) }
            } catch {
                guard generation == openGeneration else { return }
                notice = "Could not read \(doc.title): \(error.localizedDescription)"
            }
        }
    }

    /// The name of the folder that holds a document, for the card's subtitle.
    private func folderName(of doc: Document) -> String? {
        func find(_ folders: [Folder]) -> String? {
            for f in folders {
                if f.documents.contains(where: { $0.id == doc.id }) { return f.name }
                if let n = find(f.folders) { return n }
            }
            return nil
        }
        return find(tree)
    }
```

Keep the existing comment above `open` about navigation versus loading; the `Task { await followCurrentFile() }` line inside the first branch becomes the `return Task { ... }` shown.

In `reload(_:anchorText:)` change `nowPlaying?.update(title: doc.title)` to `nowPlaying?.update(title: doc.title, subtitle: currentSubtitle)`.

In `restoreLast()` (the method around line 780 that builds `doc` from the restored path) change `nowPlaying?.update(title: doc.title)` to:

```swift
            currentSubtitle = folderName(of: doc)
            nowPlaying?.update(title: doc.title, subtitle: currentSubtitle)
```

`restoreLast` runs before the first scan lands, so `folderName` is usually nil there; the first `refresh` that follows does not push the card, and that is accepted: the subtitle appears on the next open or reload.

Search the file for any other `update(title:` and change it the same way. Then delete the one-argument `update(title:)` overload from `Sources/Speech/NowPlaying.swift`.

In `Sources/Aloud/AloudApp.swift`, delete the two comment lines and the `.symbolEffect(.wiggle, value: model.shakeCount)` line in the `MenuBarExtra` label.

- [ ] **Step 5: Run the tests to verify they pass**

Run: `make test 2>&1 | grep -E "AppModel|passed|failed|error:" | head -30`
Expected: every `AppModelTests` case passes, including the four that were there.
If `playWritesOneNoteAndPlaysIt` reports the file as `Hello there..md`, that is `NoteName` keeping the sentence's full stop and then adding `.md`; the assertion accepts both.
If `aFailedWriteIsReportedOnThePanel` fails because `refresh` reports the blocked root first, note that `writeNote` throws at `makeNote` before `refresh` runs, so the panel's failure is the write's.

- [ ] **Step 6: Commit**

```bash
make check
git add Sources/Aloud/ClipboardPanelState.swift Sources/Aloud/AppModel.swift Sources/Aloud/AloudApp.swift Sources/Speech/NowPlaying.swift Tests/AloudTests/AppModelTests.swift
git commit -m "app: the hotkey previews the clipboard, and Play writes the note"
```

---

### Task 5: The panel on screen

**Files:**
- Create: `Sources/Aloud/NowPlayingArtwork.swift`
- Create: `Sources/Aloud/ClipboardPanelView.swift`
- Create: `Sources/Aloud/ClipboardPanelController.swift`
- Modify: `Sources/Aloud/AloudApp.swift`
- Modify: `Sources/Aloud/AppModel.swift` (`start()` passes the artwork)
- Test: `Tests/AloudUITests/LiteralLintTests.swift` already scans `Sources/Aloud`; the rest is checked by hand in Task 6.

**Interfaces:**
- Consumes: `ClipboardCard` from Task 3, `AppModel.clipboardPanel`, `playPreview()`, `dismissClipboardPanel()` from Task 4, `NowPlaying.init(player:artwork:)` from Task 2.
- Produces: `ClipboardPanelController(model:)`, a `@MainActor final class` that owns the panel for the life of the app; `NowPlayingArtwork.make() -> NSImage`.

- [ ] **Step 1: The artwork**

`Sources/Aloud/NowPlayingArtwork.swift`:

```swift
import AloudUI
import AppKit
import SwiftUI

/// The Now Playing card's plate: the waveform in white on the accent colour, the
/// same plate the clipboard panel draws. Rendered once at launch and handed to
/// `NowPlaying`, so the card has a picture rather than a grey square.
enum NowPlayingArtwork {
    @MainActor static func make() -> NSImage? {
        let plate = RoundedRectangle(cornerRadius: Radius.plate, style: .continuous)
            .fill(Ink.plate)
            .frame(width: Size.clipboardPlate, height: Size.clipboardPlate)
            .overlay {
                Image(systemName: "waveform")
                    .resizable().scaledToFit()
                    .frame(width: Size.clipboardGlyph, height: Size.clipboardGlyph)
                    .foregroundStyle(Ink.plateGlyph)
            }
        let renderer = ImageRenderer(content: plate)
        renderer.scale = NSScreen.main?.backingScaleFactor ?? 1
        return renderer.nsImage
    }
}
```

In `AppModel.start()`, change `nowPlaying = NowPlaying(player: player)` to `nowPlaying = NowPlaying(player: player, artwork: NowPlayingArtwork.make())`.

- [ ] **Step 2: The view**

`Sources/Aloud/ClipboardPanelView.swift`:

```swift
import AloudUI
import AppKit
import Speech
import SwiftUI

/// The clipboard card bound to the model: the strings come from the panel's state,
/// and the transport drives the one player once the note is playing.
struct ClipboardPanelView: View {
    var model: AppModel
    /// Where the card's Play is handed up to the controller, so a key press does
    /// exactly what a click does, `openWindow` included, which only a view in the
    /// hierarchy can reach.
    let actions: PanelActions
    @Environment(\.openWindow) private var openWindow
    var player: Player { model.player }

    var body: some View {
        // Nil draws an empty card for the instant between dismiss and order-out; the
        // controller never leaves the panel up over it.
        let state = model.clipboardPanel ?? .empty
        card(for: state)
            .onChange(of: model.clipboardPanel, initial: true) { _, now in
                actions.play = { if let now { play(now) } }
            }
    }

    func card(for state: ClipboardPanelState) -> some View {
        ClipboardCard(
            title: title(for: state), subtitle: subtitle(for: state), transport: transport(for: state),
            progress: isPlayer(state) ? player.progress : 0,
            elapsed: Format.clock(isPlayer(state) ? player.elapsed : .zero),
            remaining: "~" + Format.clock(remaining(for: state)),
            skipSeconds: AloudApp.skipStep,
            onPlay: { play(state) },
            onBack: { player.skip(seconds: -Player.skipSeconds) },
            onForward: { player.skip(seconds: Player.skipSeconds) },
            onSeek: { player.seek(progress: $0) })
    }

    func isPlayer(_ s: ClipboardPanelState) -> Bool {
        if case .playing = s { return true }
        return false
    }

    func title(for s: ClipboardPanelState) -> String {
        s.preview?.title ?? "Nothing to read"
    }

    func subtitle(for s: ClipboardPanelState) -> String {
        switch s {
        case .empty: "The clipboard has no text"
        case .needsFolder: "Pick a folder in Aloud first"
        case .preview(_, let failure?): failure
        case .preview(let p, nil), .playing(let p):
            "From clipboard · ~\(Format.minutes(p.estimate(factor: player.rate.factor))) · \(p.words) words"
        }
    }

    func transport(for s: ClipboardPanelState) -> ClipboardCard.Transport {
        switch s {
        case .empty: .disabled
        case .preview, .needsFolder: .ready
        case .playing: .playing(isPlaying: player.isPlaying)
        }
    }

    func remaining(for s: ClipboardPanelState) -> Duration {
        switch s {
        case .playing: player.remaining
        case .empty: .zero
        case .preview(let p, _), .needsFolder(let p): p.estimate(factor: player.rate.factor)
        }
    }

    /// Play before the note exists writes it; after, it is the player's toggle. With
    /// no folder it opens the window, where one can be picked.
    func play(_ s: ClipboardPanelState) {
        switch s {
        case .empty: break
        case .preview: model.playPreview()
        case .playing: player.toggle()
        case .needsFolder:
            model.dismissClipboardPanel()
            openWindow(id: AloudApp.mainWindowID)
            NSApp.activate()
        }
    }
}
```

`Format.minutes` returns `3 min`, so the subtitle reads `From clipboard · ~3 min · 412 words`.

- [ ] **Step 3: The controller**

`Sources/Aloud/ClipboardPanelController.swift`:

```swift
import AloudUI
import AppKit
import SwiftUI

/// Owns the one floating panel and keeps it in step with `model.clipboardPanel`:
/// non-nil orders it front under the menu bar, nil orders it out.
///
/// The panel is non-activating and is made key rather than merely ordered front:
/// Aloud stays inactive and the app in front stays in front, but Enter, Space and
/// Escape reach the panel while it is up, the way they reach Spotlight. Resigning
/// key - a click anywhere else - is the dismissal.
/// The card's Play, as the view in the panel last set it. A key press goes through it
/// so Enter does what a click does in every state.
@MainActor
final class PanelActions {
    var play: () -> Void = {}
}

@MainActor
final class ClipboardPanelController: NSObject, NSWindowDelegate {
    private let model: AppModel
    private let panel: NSPanel
    private let actions = PanelActions()
    private var observation: Task<Void, Never>?
    private var keyMonitor: Any?

    init(model: AppModel) {
        self.model = model
        panel = NSPanel(
            contentRect: .zero, styleMask: [.nonactivatingPanel, .borderless, .fullSizeContentView],
            backing: .buffered, defer: true)
        super.init()
        panel.level = .floating
        panel.hidesOnDeactivate = false
        panel.isFloatingPanel = true
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = true
        panel.isMovable = false
        panel.delegate = self
        let host = NSHostingView(rootView: ClipboardPanelView(model: model, actions: actions))
        host.sizingOptions = [.intrinsicContentSize]
        panel.contentView = host
        observe()
    }

    deinit {
        observation?.cancel()
    }

    /// Re-runs whenever the state flips between nil and not, the way `NowPlaying`
    /// follows the player. Only presence is observed: the view redraws its own contents.
    private func observe() {
        observation = Task { [weak self] in
            let stream = Observations { [weak self] in self?.model.clipboardPanel != nil }
            for await shown in stream {
                guard let self else { return }
                if shown { self.show() } else { self.hide() }
            }
        }
    }

    private func show() {
        panel.contentView?.layoutSubtreeIfNeeded()
        let size = panel.contentView?.fittingSize ?? .zero
        // The screen that carries the menu bar is the one whose origin is the origin,
        // so the panel is in the same place every time, never under the cursor.
        let screen = NSScreen.screens.first { $0.frame.origin == .zero } ?? NSScreen.main
        guard let screen else { return }
        let visible = screen.visibleFrame
        let origin = NSPoint(
            x: visible.midX - size.width / 2, y: visible.maxY - Space.s - size.height)
        panel.setFrame(NSRect(origin: origin, size: size), display: true)
        installKeys()
        panel.makeKeyAndOrderFront(nil)
    }

    private func hide() {
        removeKeys()
        panel.orderOut(nil)
    }

    /// Enter and Space play, Escape dismisses. A local monitor, since the panel is
    /// key while it is up and every keystroke reaches Aloud; the card's own buttons
    /// are the transport's, and these are the shortcuts to them.
    private func installKeys() {
        guard keyMonitor == nil else { return }
        keyMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
            guard let self, self.panel.isKeyWindow else { return event }
            switch event.keyCode {
            case Keys.escape:
                self.model.dismissClipboardPanel()
                return nil
            case Keys.enter, Keys.keypadEnter, Keys.space:
                self.press()
                return nil
            default:
                return event
            }
        }
    }

    private func removeKeys() {
        if let keyMonitor { NSEvent.removeMonitor(keyMonitor) }
        keyMonitor = nil
    }

    /// The same as the card's play button: the view decides what Play means in each
    /// state and hands the decision up, and the key goes through it.
    private func press() {
        actions.play()
    }

    // MARK: NSWindowDelegate

    /// A click anywhere outside: the panel is no longer key, which is the dismissal.
    /// After Play the note stays and keeps playing; only the panel goes.
    func windowDidResignKey(_ notification: Notification) {
        model.dismissClipboardPanel()
    }

    /// The virtual key codes the monitor reads. Carbon's names, without Carbon.
    private enum Keys {
        static let escape: UInt16 = 53
        static let enter: UInt16 = 36
        static let keypadEnter: UInt16 = 76
        static let space: UInt16 = 49
    }
}
```

Key codes are numbers, but not layout tokens; the lint patterns do not match `: UInt16 =`.
They live in this file because they are AppKit's, not the design system's.

`PanelActions` is a plain class rather than `@Observable` on purpose: nothing renders it, and an observed write from inside `onChange` would invalidate the view that made it.

- [ ] **Step 4: Install it from the app**

In `Sources/Aloud/AloudApp.swift`:

Add a property under `@State private var model: AppModel`:

```swift
    /// The clipboard panel's owner, alive with the window closed: it is not a scene,
    /// so it is made here beside the model rather than in the body.
    @State private var clipboardPanel: ClipboardPanelController
```

In `init()`, after `_model = State(...)`:

```swift
        _clipboardPanel = State(
            initialValue: MainActor.assumeIsolated { ClipboardPanelController(model: _model.wrappedValue) })
```

`_model.wrappedValue` is readable in `init` after the assignment above it; if the compiler objects, build the model into a local `let m = AppModel(...)` first and pass `m` to both `State` initialisers.

- [ ] **Step 5: Build, lint, and run the tests**

Run: `make check && make test 2>&1 | tail -5`
Expected: lint clean, build clean, every test passes.
If `Observations` will not take the `[weak self]` closure returning a `Bool`, mirror the shape in `NowPlaying.observe()`, which returns a tuple; a one-element tuple is `(self?.model.clipboardPanel != nil)` with a trailing comma inside parentheses removed, or simply return the `Bool`.

- [ ] **Step 6: Commit**

```bash
git add Sources/Aloud/NowPlayingArtwork.swift Sources/Aloud/ClipboardPanelView.swift Sources/Aloud/ClipboardPanelController.swift Sources/Aloud/AloudApp.swift Sources/Aloud/AppModel.swift
git commit -m "app: a floating clipboard panel under the menu bar, and a plate on the Now Playing card"
```

---

### Task 6: Check it by hand

**Files:** none changed unless a check fails.

The panel's placement and its keys are AppKit and are checked by hand, which the spec calls for.
Each check below is one run of `make dev` with the app's window in the state named.

- [ ] **Step 1: From Safari, window closed**

Close Aloud's window, leave it running. Copy a paragraph in Safari and press Ctrl+Option+Space.
Expected: the panel appears centred under the menu bar, Safari stays in front, the title is the paragraph's first line, the subtitle is `From clipboard · ~N min · N words`, Play alone is enabled, the scrubber reads `0:00` and `~N:NN`.
Press Space.
Expected: speech starts, the panel becomes the mini player, the scrubber moves, the play button is a pause.
Press Escape.
Expected: the panel goes and speech continues; the menu-bar glyph animates.

- [ ] **Step 2: Empty clipboard**

Copy nothing (`pbcopy < /dev/null` in a terminal), press the hotkey.
Expected: `Nothing to read` over `The clipboard has no text`, transport disabled, gone by itself after about a second and a half. The menu-bar glyph does not wiggle.

- [ ] **Step 3: No folder**

Detach every folder in Settings, copy text, press the hotkey.
Expected: subtitle `Pick a folder in Aloud first`. Click Play.
Expected: the panel goes and Aloud's window comes to the front.

- [ ] **Step 4: Hotkey while open**

With the panel open and playing, copy different text and press the hotkey.
Expected: the preview swaps to the new text, the transport returns to Play alone, speech continues. Press the hotkey again without copying: nothing changes.

- [ ] **Step 5: Full-screen app and a second display**

Put Safari in full screen, press the hotkey.
Expected: the panel shows over the full-screen space. With an external display, the panel is on the display that carries the menu bar whichever display has the cursor.

- [ ] **Step 6: The system card**

While a note from the panel plays, open Control Center's Now Playing.
Expected: the plate is the waveform on the accent, the subtitle is `From clipboard`. Open a document from the library.
Expected: the subtitle is its folder's name.

- [ ] **Step 7: Click outside**

Open the panel, click Safari's page.
Expected: the panel goes; Safari never lost its place.

- [ ] **Step 8: Fix and commit anything that failed**

If a check fails, fix it within the files this plan names, run `make check && make test`, and commit with an `app:` message that says what was wrong.

---

## Self-review against the spec

- Panel under the menu bar, non-activating, on the menu bar's display, centred, `Space.s` below `visibleFrame.maxY`: Task 5 `show()`.
- Now Playing layout, plate at left, title and subtitle, transport, scrubber: Task 3.
- Before Play: title from `Title.from`, subtitle `From clipboard · ~3 min · 412 words`, Play alone, scrubber empty: Tasks 1, 3, 5.
- Play writes through the existing note path, panel becomes a mini player on the one player: Task 4 `playPreview` and `writeNote`, Task 5 view.
- Enter or Space plays, Escape dismisses, click outside dismisses: Task 5 keys and `windowDidResignKey`.
- Dismiss before Play leaves nothing, after Play keeps playing: Task 4 tests.
- Hotkey while open: different text swaps, same text no-op, playing same text no-op: Task 4 `preview(clipboard:)` and tests.
- Empty clipboard: `Nothing to read`, `The clipboard has no text`, disabled, self-dismiss after `Motion.emptyPanelHold`, wiggle removed: Tasks 3, 4, 5.
- No folder: `Pick a folder in Aloud first`, Play opens the window: Tasks 4, 5.
- Now Playing subtitle (folder name, `From clipboard`) and artwork: Tasks 2, 4, 5.
- `ClipboardPreview` in `Vault` with trim, title, words, estimate: Task 1.
- Model state enum with four cases, `previewClipboard`, `playPreview`, `dismissClipboardPanel`, hotkey calls `previewClipboard`: Task 4.
- Controller flags and placement, `NSHostingView`, observation, installed beside the scenes: Task 5.
- Tokens `clipboardPanelWidth` 360, `clipboardPlate` 88, `emptyPanelHold` 1.6, `panelTitle`, `panelSubtitle`; gallery in four states; lint covers the new files: Task 3.
- Error handling: a failed write shows in the subtitle's place and Play is live again: Task 4 `.preview(_, failure:)` and its test.
- Tests named in the spec: `ClipboardPreviewTests` (Task 1), `AppModelTests` cases (Task 4), `NowPlayingTests` subtitle and artwork (Task 2), hand checks (Task 6).
- Out of scope, untouched: no rate button on the panel; text only; the menu-bar panel and Cmd+Shift+V still write at once, though Cmd+Shift+V now waits for the load before playing, which is the bug fix named above.
