# Aloud Core Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** A macOS 26 app that opens a vault folder, shows its `.md` and `.txt` files as a grid, and reads one aloud with Apple voices, sentence and word highlight, seek, rate, and a persistent transport bar.

**Architecture:** One Swift package with four libraries (`AloudUI`, `Prose`, `Vault`, `Speech`) and a thin SwiftUI executable (`Aloud`).
All rules live in the libraries and are tested with `swift test`; the app composes `AloudUI` components and draws.
A `Makefile` gives the `npm run dev` loop with the command-line tools alone.

**Tech Stack:** Swift 6.2, Swift 6 language mode, SwiftUI with Liquid Glass (macOS 26), Swift Testing, swift-markdown, NaturalLanguage, AVFoundation, FSEvents, AppKit `NSTextView` for the reader body, XcodeGen (later), watchexec (dev).

**Spec:** `docs/superpowers/specs/2026-09-09-aloud-design.md`

This is plan 1 of 2 and covers spec milestones 1 to 5.
Plan 2 covers PDF, paste-to-note, drop, search, the voice popover, the menu-bar player, the hotkey, Settings and Now Playing.

## Global Constraints

- Repo is `~/aloud`; app target `Aloud`; bundle id `design.kevxu.aloud`.
- macOS 26 only; `platforms: [.macOS(.v26)]`; Swift 6 language mode with strict concurrency in every target.
- No number, colour, font size or duration literal outside `Sources/AloudUI/Tokens.swift`; a test enforces it over `Sources/AloudUI` and `Sources/Aloud`.
- Sentence splitting is the `Prose.SentenceSplitter` rule everywhere: terminal punctuation followed by whitespace, with an abbreviation guard, since `NLTokenizer` does not split before a lowercase sentence start.
- Duration estimate is 160 words per minute at rate 1.0, scaled linearly by the rate factor.
- Rate steps are exactly 0.75, 1, 1.25, 1.5, 1.75, 2, 2.5, 3.
- Speech is one utterance per sentence.
- Progress is stored in Application Support as JSON keyed by file path, never in the user's files.
- Every commit passes `make check` and `make test`.
- Writing rules from the user's global CLAUDE.md apply to every Markdown file: no em dash, one sentence per line in long files.
- Commit messages carry no co-author line.

---

## File structure

```
Package.swift
Makefile
.swift-format
.gitignore
App/Info.plist                         bundle metadata for the assembled .app
Sources/
  AloudUI/
    Tokens.swift                       the only file with literals
    Components/GlassBar.swift
    Components/Card.swift
    Components/FolderCard.swift
    Components/IconButton.swift
    Components/TransportButton.swift
    Components/RateButton.swift
    Components/Scrubber.swift
    Components/EmptyState.swift
    Components/Notice.swift
    Modifiers/Highlight.swift          NSColor forms of the two highlight tokens for the text view
    Gallery.swift                      every component in every state
  Prose/
    Script.swift                       Sentence, Script
    SentenceSplitter.swift             NLTokenizer per paragraph
    Estimate.swift                     160 wpm
    Extractor.swift                    protocol, ExtractOptions, Extractors.for(type)
    PlainTextExtractor.swift
    MarkdownExtractor.swift            MarkupWalker over swift-markdown
    Extraction.swift                   actor, cache keyed by (path, mtime)
  Vault/
    DocumentType.swift
    Document.swift                     Document, Folder
    Title.swift                        title from first heading or first line
    Scanner.swift                      walk a root into a Folder
    NoteName.swift                     file name for a pasted note
    Vault.swift                        actor over roots: tree, makeNote, save
    FolderWatcher.swift                FSEvents, recursive, debounced
    ProgressStore.swift                JSON progress per path
  Speech/
    Voice.swift                        Voice, Quality
    Rate.swift                         the eight steps and the AVSpeech mapping
    Timeline.swift                     estimated start time per sentence
    VoiceProvider.swift                protocol
    FakeVoiceProvider.swift            test double, shipped so the app can run silent
    Player.swift                       @Observable, sentence chaining, seek, skip
    AppleVoiceProvider.swift           AVSpeechSynthesizer
  Aloud/
    AloudApp.swift                     @main, --gallery and --say flags
    AppModel.swift                     vault, player, progress, route
    RootStore.swift                    security-scoped bookmarks
    Route.swift
    RootView.swift                     NavigationStack plus transport overlay
    LibraryView.swift
    ReaderView.swift
    ReaderTextView.swift               NSViewRepresentable over NSTextView
    TransportBarView.swift
Tests/
  AloudUITests/LiteralLintTests.swift
  AloudUITests/GalleryTests.swift
  ProseTests/...  Fixtures/ (md and txt files with expected output)
  VaultTests/...
  SpeechTests/...
```

---

### Task 1: Package, Makefile, empty window

**Files:**
- Create: `Package.swift`, `Makefile`, `.swift-format`, `.gitignore`, `App/Info.plist`, `Sources/Aloud/AloudApp.swift`, and one placeholder file per library so the package resolves.

**Interfaces:**
- Produces: the targets `AloudUI`, `Prose`, `Vault`, `Speech`, `Aloud`; the commands `make dev`, `make watch`, `make gallery`, `make test`, `make check`.

- [ ] **Step 1: Install the two dev tools**

Run: `brew install watchexec xcodegen`
Expected: both on `PATH` (`which watchexec xcodegen`).

- [ ] **Step 2: Write `Package.swift`**

```swift
// swift-tools-version: 6.0
import PackageDescription

let strict: [SwiftSetting] = [.swiftLanguageMode(.v6)]

let package = Package(
    name: "Aloud",
    platforms: [.macOS(.v26)],
    products: [
        .executable(name: "Aloud", targets: ["Aloud"]),
    ],
    dependencies: [
        .package(url: "https://github.com/swiftlang/swift-markdown.git", from: "0.5.0"),
    ],
    targets: [
        .target(name: "AloudUI", swiftSettings: strict),
        .target(
            name: "Prose",
            dependencies: [.product(name: "Markdown", package: "swift-markdown")],
            swiftSettings: strict),
        .target(name: "Vault", swiftSettings: strict),
        .target(name: "Speech", dependencies: ["Prose"], swiftSettings: strict),
        .executableTarget(
            name: "Aloud",
            dependencies: ["AloudUI", "Prose", "Vault", "Speech"],
            swiftSettings: strict),
        .testTarget(name: "AloudUITests", dependencies: ["AloudUI", "Aloud"], swiftSettings: strict),
        .testTarget(
            name: "ProseTests", dependencies: ["Prose"],
            resources: [.copy("Fixtures")], swiftSettings: strict),
        .testTarget(name: "VaultTests", dependencies: ["Vault"], swiftSettings: strict),
        .testTarget(name: "SpeechTests", dependencies: ["Speech"], swiftSettings: strict),
    ]
)
```

- [ ] **Step 3: Placeholder sources so every target compiles**

`Sources/AloudUI/Tokens.swift`, `Sources/Prose/Script.swift`, `Sources/Vault/Document.swift`, `Sources/Speech/Voice.swift` each contain one line for now:

```swift
import Foundation
```

`Tests/ProseTests/Fixtures/.keep` empty file so the resource directory exists.

- [ ] **Step 4: The app**

`Sources/Aloud/AloudApp.swift`:

```swift
import SwiftUI

@main
struct AloudApp: App {
    var body: some Scene {
        WindowGroup("Aloud") {
            Text("Aloud")
        }
    }
}
```

- [ ] **Step 5: `App/Info.plist`**

```xml
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>CFBundleDevelopmentRegion</key><string>en</string>
    <key>CFBundleExecutable</key><string>Aloud</string>
    <key>CFBundleIdentifier</key><string>design.kevxu.aloud</string>
    <key>CFBundleInfoDictionaryVersion</key><string>6.0</string>
    <key>CFBundleName</key><string>Aloud</string>
    <key>CFBundlePackageType</key><string>APPL</string>
    <key>CFBundleShortVersionString</key><string>0.1.0</string>
    <key>CFBundleVersion</key><string>1</string>
    <key>LSMinimumSystemVersion</key><string>26.0</string>
    <key>NSPrincipalClass</key><string>NSApplication</string>
    <key>NSHighResolutionCapable</key><true/>
</dict>
</plist>
```

- [ ] **Step 6: `Makefile`**

```make
APP := .build/Aloud.app
BIN := .build/debug/Aloud

.PHONY: dev watch gallery build bundle test check clean

dev: build bundle
	@pkill -x Aloud || true
	@open $(APP)

gallery: build bundle
	@pkill -x Aloud || true
	@open $(APP) --args --gallery

watch:
	watchexec -e swift,plist -r --debounce 300ms -- make dev

build:
	swift build --product Aloud

bundle:
	@mkdir -p $(APP)/Contents/MacOS $(APP)/Contents/Resources
	@cp $(BIN) $(APP)/Contents/MacOS/Aloud
	@cp App/Info.plist $(APP)/Contents/Info.plist

test:
	swift test

check:
	swift format lint --strict --recursive Sources Tests Package.swift
	swift build

clean:
	rm -rf .build
```

Tabs, not spaces, in the recipe lines.

- [ ] **Step 7: `.swift-format` and `.gitignore`**

`.swift-format`:

```json
{
  "version": 1,
  "lineLength": 110,
  "indentation": { "spaces": 4 },
  "rules": { "AlwaysUseLowerCamelCase": true, "NeverForceUnwrap": false }
}
```

`.gitignore`:

```
.build/
*.xcodeproj
.DS_Store
```

- [ ] **Step 8: Build, run, and see the window**

Run: `make dev`
Expected: a window titled Aloud with the word Aloud in it.
Run: `make check` and `make test`
Expected: both exit 0 (no tests yet is fine).

- [ ] **Step 9: Commit**

```bash
git add -A && git commit -m "build: package, makefile, empty window"
```

---

### Task 2: Tokens and the literal lint

**Files:**
- Create: `Sources/AloudUI/Tokens.swift`, `Tests/AloudUITests/LiteralLintTests.swift`

**Interfaces:**
- Produces: `Space`, `Radius`, `Size`, `Ink`, `Type`, `Motion` enums with static members, used by every later view.

- [ ] **Step 1: The lint test**

```swift
import Foundation
import Testing

@Suite struct LiteralLintTests {
    static let root = URL(fileURLWithPath: #filePath)
        .deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()

    static let patterns: [String] = [
        #"\.padding\(\s*\d"#,
        #"\.padding\(\.[a-zA-Z]+,\s*\d"#,
        #"spacing:\s*\d"#,
        #"(minimum|maximum|width|height|minWidth|maxWidth|minHeight|maxHeight):\s*\d"#,
        #"cornerRadius:\s*\d"#,
        #"\.font\(\.system\(size"#,
        #"Color\((red|\.sRGB|white|hue)"#,
        #"\.opacity\(\s*0?\.\d"#,
        #"duration:\s*\d"#,
        #"lineWidth:\s*\d"#,
    ]

    static func swiftFiles(under dir: String) -> [URL] {
        let base = root.appendingPathComponent(dir)
        let e = FileManager.default.enumerator(at: base, includingPropertiesForKeys: nil)!
        return e.compactMap { $0 as? URL }.filter { $0.pathExtension == "swift" }
            .filter { $0.lastPathComponent != "Tokens.swift" }
    }

    @Test func noLiteralsOutsideTokens() throws {
        var hits: [String] = []
        for dir in ["Sources/AloudUI", "Sources/Aloud"] {
            for file in Self.swiftFiles(under: dir) {
                let text = try String(contentsOf: file, encoding: .utf8)
                for (n, line) in text.split(separator: "\n", omittingEmptySubsequences: false).enumerated() {
                    for p in Self.patterns where line.range(of: p, options: .regularExpression) != nil {
                        hits.append("\(file.lastPathComponent):\(n + 1): \(line.trimmingCharacters(in: .whitespaces))")
                    }
                }
            }
        }
        #expect(hits.isEmpty, "literals outside Tokens.swift:\n" + hits.joined(separator: "\n"))
    }
}
```

- [ ] **Step 2: Run it**

Run: `swift test --filter LiteralLintTests`
Expected: PASS (nothing to catch yet). Add a temporary `.padding(8)` to `AloudApp.swift`, run again, expect FAIL naming the line, then remove it.

- [ ] **Step 3: Tokens**

`Sources/AloudUI/Tokens.swift`:

```swift
import SwiftUI

public enum Space {
    public static let xs: CGFloat = 4
    public static let s: CGFloat = 8
    public static let m: CGFloat = 12
    public static let l: CGFloat = 16
    public static let xl: CGFloat = 24
    public static let xxl: CGFloat = 32
    public static let xxxl: CGFloat = 48
}

public enum Radius {
    public static let s: CGFloat = 8
    public static let m: CGFloat = 12
    public static let l: CGFloat = 20
}

public enum Size {
    public static let icon: CGFloat = 16
    public static let control: CGFloat = 32
    public static let playControl: CGFloat = 44
    public static let hairline: CGFloat = 1
    public static let cardWidth: CGFloat = 160
    public static let thumb = CGSize(width: 120, height: 150)
    public static let minWindow = CGSize(width: 720, height: 480)
    public static let readerMeasure: CGFloat = 680
    public static let scrubberTrack: CGFloat = 4
}

public enum Ink {
    public static let primary = Color.primary
    public static let soft = Color.secondary
    public static let accent = Color.accentColor
    public static let paper = Color(nsColor: .textBackgroundColor)
    public static let highlightSentence = Color.accentColor.opacity(0.18)
    public static let highlightWord = Color.accentColor.opacity(0.45)
    public static let nsHighlightSentence = NSColor.controlAccentColor.withAlphaComponent(0.18)
    public static let nsHighlightWord = NSColor.controlAccentColor.withAlphaComponent(0.45)
}

public enum Type {
    public static let title = Font.title2.weight(.semibold)
    public static let cardTitle = Font.callout.weight(.medium)
    public static let caption = Font.caption
    public static let control = Font.body.weight(.medium)
    public static let thumb = Font.system(size: 3, design: .monospaced)
    /// The five reader sizes, indexed by the A/A stepper.
    public static let readerSizes: [CGFloat] = [15, 17, 19, 22, 26]
    public static let readerDefaultIndex = 1
    public static let readerLineHeightMultiple: CGFloat = 1.45
}

public enum Motion {
    public static let fast: Double = 0.15
    public static let normal: Double = 0.25
    public static let ease = Animation.easeOut(duration: normal)
    public static let quick = Animation.easeOut(duration: fast)
}
```

- [ ] **Step 4: Run check and test, commit**

Run: `make check && make test`
Expected: exit 0.

```bash
git add -A && git commit -m "ui: tokens and the literal lint"
```

---

### Task 3: Components and the gallery

**Files:**
- Create: `Sources/AloudUI/Components/*.swift`, `Sources/AloudUI/Gallery.swift`, `Tests/AloudUITests/GalleryTests.swift`
- Modify: `Sources/Aloud/AloudApp.swift`

**Interfaces:**
- Produces: `GlassBar`, `Card`, `FolderCard`, `IconButton`, `TransportButton`, `RateButton`, `Scrubber`, `EmptyState`, `Notice`, `Gallery` with the exact signatures below.

- [ ] **Step 1: Smoke test**

```swift
import SwiftUI
import Testing
@testable import AloudUI

@Suite @MainActor struct GalleryTests {
    @Test func galleryBuilds() {
        let g = Gallery()
        _ = g.body
        #expect(Gallery.sections.count >= 8)
    }
}
```

Run: `swift test --filter GalleryTests` → FAIL, `Gallery` undefined.

- [ ] **Step 2: Components**

`Components/GlassBar.swift`:

```swift
import SwiftUI

/// A Liquid Glass bar; content lays out horizontally inside it.
public struct GlassBar<Content: View>: View {
    let content: Content
    public init(@ViewBuilder content: () -> Content) { self.content = content() }
    public var body: some View {
        HStack(spacing: Space.l) { content }
            .padding(.horizontal, Space.xl)
            .padding(.vertical, Space.m)
            .glassEffect(.regular, in: .rect(cornerRadius: Radius.l))
    }
}
```

`Components/Card.swift`:

```swift
import SwiftUI

public struct Card: View {
    public let title: String
    public let preview: String
    public let status: String
    public init(title: String, preview: String, status: String) {
        self.title = title; self.preview = preview; self.status = status
    }
    public var body: some View {
        VStack(spacing: Space.s) {
            Text(preview)
                .font(Type.thumb)
                .foregroundStyle(Color.black)
                .frame(width: Size.thumb.width, height: Size.thumb.height, alignment: .topLeading)
                .padding(Space.s)
                .background(Color.white, in: .rect(cornerRadius: Radius.s))
                .clipped()
            Text(title)
                .font(Type.cardTitle)
                .multilineTextAlignment(.center)
                .lineLimit(2)
            Text(status)
                .font(Type.caption)
                .foregroundStyle(Ink.soft)
        }
        .frame(width: Size.cardWidth)
    }
}
```

`Components/FolderCard.swift`:

```swift
import SwiftUI

public struct FolderCard: View {
    public let name: String
    public let count: Int
    public init(name: String, count: Int) { self.name = name; self.count = count }
    public var body: some View {
        VStack(spacing: Space.s) {
            Image(systemName: "folder.fill")
                .resizable().scaledToFit()
                .foregroundStyle(Ink.accent)
                .frame(width: Size.thumb.width, height: Size.thumb.height)
            Text(name).font(Type.cardTitle).lineLimit(2)
            Text(count == 0 ? "Empty folder" : "\(count) documents")
                .font(Type.caption).foregroundStyle(Ink.soft)
        }
        .frame(width: Size.cardWidth)
    }
}
```

`Components/IconButton.swift`:

```swift
import SwiftUI

public struct IconButton: View {
    let symbol: String
    let label: String
    let action: () -> Void
    public init(_ symbol: String, label: String, action: @escaping () -> Void) {
        self.symbol = symbol; self.label = label; self.action = action
    }
    public var body: some View {
        Button(action: action) {
            Image(systemName: symbol)
                .frame(width: Size.control, height: Size.control)
        }
        .buttonStyle(.glass)
        .accessibilityLabel(label)
        .help(label)
    }
}
```

`Components/TransportButton.swift`:

```swift
import SwiftUI

public struct TransportButton: View {
    public enum Kind { case back15, play, pause, forward15 }
    let kind: Kind
    let action: () -> Void
    public init(_ kind: Kind, action: @escaping () -> Void) { self.kind = kind; self.action = action }
    var symbol: String {
        switch kind {
        case .back15: "15.arrow.trianglehead.counterclockwise"
        case .play: "play.fill"
        case .pause: "pause.fill"
        case .forward15: "15.arrow.trianglehead.clockwise"
        }
    }
    var label: String {
        switch kind {
        case .back15: "Back 15 seconds"
        case .play: "Play"
        case .pause: "Pause"
        case .forward15: "Forward 15 seconds"
        }
    }
    var size: CGFloat { kind == .play || kind == .pause ? Size.playControl : Size.control }
    public var body: some View {
        Button(action: action) {
            Image(systemName: symbol)
                .resizable().scaledToFit()
                .frame(width: size, height: size)
                .padding(Space.xs)
        }
        .buttonStyle(.plain)
        .accessibilityLabel(label)
        .help(label)
    }
}
```

`Components/RateButton.swift`:

```swift
import SwiftUI

/// Click cycles to the next step, the menu picks any step.
public struct RateButton: View {
    let label: String
    let all: [String]
    let onCycle: () -> Void
    let onPick: (Int) -> Void
    public init(label: String, all: [String], onCycle: @escaping () -> Void, onPick: @escaping (Int) -> Void) {
        self.label = label; self.all = all; self.onCycle = onCycle; self.onPick = onPick
    }
    public var body: some View {
        Button(label, action: onCycle)
            .font(Type.control)
            .buttonStyle(.glass)
            .contextMenu {
                ForEach(Array(all.enumerated()), id: \.offset) { i, s in
                    Button(s) { onPick(i) }
                }
            }
            .accessibilityLabel("Speed \(label)")
    }
}
```

`Components/Scrubber.swift`:

```swift
import SwiftUI

/// Elapsed and remaining labels around a seekable track. `progress` is 0...1.
public struct Scrubber: View {
    let progress: Double
    let elapsed: String
    let remaining: String
    let onSeek: (Double) -> Void
    public init(progress: Double, elapsed: String, remaining: String, onSeek: @escaping (Double) -> Void) {
        self.progress = progress; self.elapsed = elapsed; self.remaining = remaining; self.onSeek = onSeek
    }
    public var body: some View {
        HStack(spacing: Space.m) {
            Text(elapsed).font(Type.caption).foregroundStyle(Ink.soft).monospacedDigit()
            GeometryReader { geo in
                ZStack(alignment: .leading) {
                    Capsule().fill(Ink.soft.opacity(0.3))
                    Capsule().fill(Ink.primary).frame(width: geo.size.width * progress)
                }
                .contentShape(Rectangle())
                .gesture(DragGesture(minimumDistance: 0).onEnded { v in
                    onSeek(min(max(v.location.x / geo.size.width, 0), 1))
                })
            }
            .frame(height: Size.scrubberTrack)
            Text(remaining).font(Type.caption).foregroundStyle(Ink.soft).monospacedDigit()
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel("Position \(elapsed), \(remaining) remaining")
    }
}
```

The `.opacity(0.3)` here is a literal; move it into Tokens as `Ink.track = Color.secondary.opacity(0.3)` and use `Ink.track`.
The lint will catch it if you forget.

`Components/EmptyState.swift`:

```swift
import SwiftUI

public struct EmptyState: View {
    let onPickFolder: () -> Void
    let onPaste: () -> Void
    public init(onPickFolder: @escaping () -> Void, onPaste: @escaping () -> Void) {
        self.onPickFolder = onPickFolder; self.onPaste = onPaste
    }
    public var body: some View {
        VStack(spacing: Space.l) {
            Text("Aloud reads your files to you.").font(Type.title)
            HStack(spacing: Space.m) {
                Button("Pick a folder to read from", action: onPickFolder).buttonStyle(.glassProminent)
                Button("Paste anything", action: onPaste).buttonStyle(.glass)
            }
        }
        .padding(Space.xxl)
        .glassEffect(.regular, in: .rect(cornerRadius: Radius.l))
    }
}
```

`Components/Notice.swift`:

```swift
import SwiftUI

public struct Notice: View {
    let text: String
    public init(_ text: String) { self.text = text }
    public var body: some View {
        Label(text, systemImage: "exclamationmark.triangle")
            .font(Type.caption)
            .padding(.horizontal, Space.m).padding(.vertical, Space.s)
            .glassEffect(.regular, in: .capsule)
    }
}
```

- [ ] **Step 3: Gallery**

```swift
import SwiftUI

public struct Gallery: View {
    public static let sections = [
        "GlassBar", "Card", "FolderCard", "IconButton", "TransportButton",
        "RateButton", "Scrubber", "EmptyState", "Notice",
    ]
    public init() {}
    public var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: Space.xxl) {
                section("GlassBar") {
                    GlassBar { Text("Left"); Spacer(); Text("Right") }
                }
                section("Card") {
                    HStack(spacing: Space.xl) {
                        Card(title: "It's been a fast year.", preview: Self.lorem, status: "~8 min")
                        Card(title: "Managing Agents, From First Principles", preview: Self.lorem, status: "3:12 left")
                        Card(title: "Finished one", preview: Self.lorem, status: "Finished")
                    }
                }
                section("FolderCard") {
                    HStack(spacing: Space.xl) {
                        FolderCard(name: "untitled folder", count: 0)
                        FolderCard(name: "Essays", count: 12)
                    }
                }
                section("IconButton") {
                    HStack { IconButton("plus", label: "New") {}; IconButton("magnifyingglass", label: "Search") {} }
                }
                section("TransportButton") {
                    HStack {
                        TransportButton(.back15) {}; TransportButton(.play) {}
                        TransportButton(.pause) {}; TransportButton(.forward15) {}
                    }
                }
                section("RateButton") {
                    RateButton(label: "1x", all: ["0.75x", "1x", "1.25x"], onCycle: {}, onPick: { _ in })
                }
                section("Scrubber") {
                    Scrubber(progress: 0.07, elapsed: "0:34", remaining: "~8:06") { _ in }
                }
                section("EmptyState") { EmptyState(onPickFolder: {}, onPaste: {}) }
                section("Notice") { Notice("Voice not available, using the system default") }
            }
            .padding(Space.xxl)
        }
    }
    func section(_ name: String, @ViewBuilder _ content: () -> some View) -> some View {
        VStack(alignment: .leading, spacing: Space.m) {
            Text(name).font(Type.caption).foregroundStyle(Ink.soft)
            content()
        }
    }
    static let lorem = String(repeating: "nobody really teaches you research. you get a desk, a problem someone else picked. ", count: 12)
}
```

- [ ] **Step 4: `--gallery` in the app**

Replace `AloudApp.swift`:

```swift
import AloudUI
import SwiftUI

@main
struct AloudApp: App {
    static let showGallery = CommandLine.arguments.contains("--gallery")
    var body: some Scene {
        WindowGroup("Aloud") {
            if Self.showGallery { Gallery() } else { Text("Aloud") }
        }
        .defaultSize(Size.minWindow)
    }
}
```

- [ ] **Step 5: Run everything**

Run: `swift test --filter GalleryTests` → PASS. `make check` → exit 0. `make gallery` → a window with every component.
Look at it: glass on the bar and buttons, cards 160 wide, nothing clipped.

- [ ] **Step 6: Commit**

```bash
git add -A && git commit -m "ui: components and the gallery"
```

---

### Task 4: Prose: Script, sentence splitting, estimate

**Files:**
- Create: `Sources/Prose/Script.swift`, `Sources/Prose/SentenceSplitter.swift`, `Sources/Prose/Estimate.swift`, `Tests/ProseTests/SentenceSplitterTests.swift`, `Tests/ProseTests/EstimateTests.swift`

**Interfaces:**
- Produces:
  - `public struct Sentence: Hashable, Sendable { public let text: String; public let range: Range<String.Index> }`
  - `public struct Script: Hashable, Sendable { public let source: String; public let sentences: [Sentence]; public var wordCount: Int; public init(source: String, sentences: [Sentence]) }`
  - `public enum SentenceSplitter { public static func split(_ source: String) -> [Sentence] }` where paragraphs are separated by blank lines and a paragraph end always ends a sentence.
  - `public enum Estimate { public static let wordsPerMinute = 160.0; public static func duration(words: Int, factor: Double) -> Duration; public static func words(in text: String) -> Int }`

Note: the `SentenceSplitter` implementation below is this task's original, `NLTokenizer`-based design.
It was later replaced by a punctuation-rule splitter, terminal punctuation followed by whitespace with an abbreviation guard, since `NLTokenizer` does not split before a lowercase sentence start; see Global Constraints and `Sources/Prose/SentenceSplitter.swift` for the shipped rule.

- [ ] **Step 1: Failing tests**

`Tests/ProseTests/SentenceSplitterTests.swift`:

```swift
import Testing
@testable import Prose

@Suite struct SentenceSplitterTests {
    @Test func splitsSentencesAndKeepsRanges() {
        let s = "Nobody teaches you research. You get a desk.\n\nPick your own problems"
        let out = SentenceSplitter.split(s)
        #expect(out.map(\.text) == ["Nobody teaches you research.", "You get a desk.", "Pick your own problems"])
        for sen in out { #expect(String(s[sen.range]) == sen.text) }
    }
    @Test func paragraphEndEndsASentence() {
        let out = SentenceSplitter.split("a heading without a period\n\nthe body. more body.")
        #expect(out.first?.text == "a heading without a period")
        #expect(out.count == 3)
    }
    @Test func emptyIsEmpty() {
        #expect(SentenceSplitter.split("  \n\n ").isEmpty)
    }
    @Test func scriptCountsWords() {
        let sc = Script(source: "one two three. four five.", sentences: SentenceSplitter.split("one two three. four five."))
        #expect(sc.wordCount == 5)
    }
}
```

`Tests/ProseTests/EstimateTests.swift`:

```swift
import Testing
@testable import Prose

@Suite struct EstimateTests {
    @Test func oneSixtyWordsIsOneMinute() {
        #expect(Estimate.duration(words: 160, factor: 1) == .seconds(60))
    }
    @Test func doubleRateHalvesIt() {
        #expect(Estimate.duration(words: 160, factor: 2) == .seconds(30))
    }
    @Test func zeroWordsIsZero() {
        #expect(Estimate.duration(words: 0, factor: 1.25) == .zero)
    }
    @Test func countsWords() {
        #expect(Estimate.words(in: "it's a stack of smaller skills, and almost") == 8)
    }
}
```

Run: `swift test --filter ProseTests` → FAIL, types undefined.

- [ ] **Step 2: Implement**

`Script.swift`:

```swift
import Foundation

public struct Sentence: Hashable, Sendable {
    public let text: String
    public let range: Range<String.Index>
    public init(text: String, range: Range<String.Index>) { self.text = text; self.range = range }
}

public struct Script: Hashable, Sendable {
    public let source: String
    public let sentences: [Sentence]
    public let wordCount: Int
    public init(source: String, sentences: [Sentence]) {
        self.source = source
        self.sentences = sentences
        self.wordCount = sentences.reduce(0) { $0 + Estimate.words(in: $1.text) }
    }
    public static let empty = Script(source: "", sentences: [])
}
```

`SentenceSplitter.swift`:

```swift
import Foundation
import NaturalLanguage

public enum SentenceSplitter {
    /// Splits on NLTokenizer sentences inside each blank-line-separated paragraph,
    /// so a heading or a list item never runs into the line after it.
    public static func split(_ source: String) -> [Sentence] {
        var out: [Sentence] = []
        let tokenizer = NLTokenizer(unit: .sentence)
        tokenizer.string = source
        var cursor = source.startIndex
        for paragraph in paragraphRanges(in: source) {
            _ = cursor
            tokenizer.enumerateTokens(in: paragraph) { range, _ in
                let trimmed = trim(range, in: source)
                if !trimmed.isEmpty { out.append(Sentence(text: String(source[trimmed]), range: trimmed)) }
                return true
            }
            cursor = paragraph.upperBound
        }
        return out
    }

    static func paragraphRanges(in s: String) -> [Range<String.Index>] {
        var ranges: [Range<String.Index>] = []
        var start = s.startIndex
        var i = s.startIndex
        while i < s.endIndex {
            if s[i] == "\n", let next = s.index(i, offsetBy: 1, limitedBy: s.endIndex), next < s.endIndex, s[next] == "\n" {
                ranges.append(start..<i)
                var j = next
                while j < s.endIndex, s[j] == "\n" { j = s.index(after: j) }
                start = j; i = j
            } else {
                i = s.index(after: i)
            }
        }
        ranges.append(start..<s.endIndex)
        return ranges.filter { !$0.isEmpty }
    }

    static func trim(_ r: Range<String.Index>, in s: String) -> Range<String.Index> {
        var lo = r.lowerBound, hi = r.upperBound
        while lo < hi, s[lo].isWhitespace { lo = s.index(after: lo) }
        while hi > lo, s[s.index(before: hi)].isWhitespace { hi = s.index(before: hi) }
        return lo..<hi
    }
}
```

Remove the `cursor` variable if the compiler warns; it is not needed.

`Estimate.swift`:

```swift
import Foundation

public enum Estimate {
    public static let wordsPerMinute = 160.0
    public static func duration(words: Int, factor: Double) -> Duration {
        guard words > 0 else { return .zero }
        let seconds = Double(words) / wordsPerMinute * 60 / factor
        return .seconds(seconds)
    }
    public static func words(in text: String) -> Int {
        text.split(whereSeparator: { $0.isWhitespace }).count
    }
}
```

- [ ] **Step 3: Run, commit**

Run: `swift test --filter ProseTests` → all PASS. `make check`.

```bash
git add -A && git commit -m "prose: script, sentence splitter, estimate"
```

---

### Task 5: Prose: Extractor protocol and plain text

**Files:**
- Create: `Sources/Prose/Extractor.swift`, `Sources/Prose/PlainTextExtractor.swift`, `Tests/ProseTests/PlainTextExtractorTests.swift`, `Tests/ProseTests/Fixtures/plain.txt`

**Interfaces:**
- Produces:
  - `public enum SourceKind: Sendable { case markdown, plainText, pdf }`
  - `public struct ExtractOptions: Sendable { public var skipCode: Bool; public static let `default` }`
  - `public protocol Extractor: Sendable { func script(from data: Data, options: ExtractOptions) throws -> Script }`
  - `public enum ExtractError: Error { case undecodable, unsupported(SourceKind) }`
  - `public enum Extractors { public static func extractor(for kind: SourceKind) throws -> any Extractor }` (pdf throws `.unsupported` until plan 2)

- [ ] **Step 1: Fixture and failing test**

`Fixtures/plain.txt`:

```
nobody really teaches you research. you get a desk.
this line continues the paragraph.

pick your own problems
```

```swift
import Foundation
import Testing
@testable import Prose

@Suite struct PlainTextExtractorTests {
    func fixture(_ name: String) throws -> Data {
        try Data(contentsOf: Bundle.module.url(forResource: name, withExtension: nil, subdirectory: "Fixtures")!)
    }
    @Test func joinsLinesInsideAParagraph() throws {
        let s = try PlainTextExtractor().script(from: fixture("plain.txt"), options: .default)
        #expect(s.source == "nobody really teaches you research. you get a desk. this line continues the paragraph.\n\npick your own problems")
        #expect(s.sentences.map(\.text) == [
            "nobody really teaches you research.", "you get a desk.",
            "this line continues the paragraph.", "pick your own problems",
        ])
    }
    @Test func rejectsNonUTF8() {
        #expect(throws: ExtractError.self) {
            try PlainTextExtractor().script(from: Data([0xFF, 0xFE, 0x00]), options: .default)
        }
    }
    @Test func registryKnowsKinds() throws {
        _ = try Extractors.extractor(for: .plainText)
        #expect(throws: ExtractError.self) { try Extractors.extractor(for: .pdf) }
    }
}
```

Run: FAIL.

- [ ] **Step 2: Implement**

`Extractor.swift`:

```swift
import Foundation

public enum SourceKind: Sendable, Hashable { case markdown, plainText, pdf }

public struct ExtractOptions: Sendable, Hashable {
    public var skipCode: Bool
    public init(skipCode: Bool = true) { self.skipCode = skipCode }
    public static let `default` = ExtractOptions()
}

public enum ExtractError: Error, Equatable { case undecodable, unsupported(SourceKind) }

public protocol Extractor: Sendable {
    func script(from data: Data, options: ExtractOptions) throws -> Script
}

public enum Extractors {
    public static func extractor(for kind: SourceKind) throws -> any Extractor {
        switch kind {
        case .plainText: PlainTextExtractor()
        case .markdown: MarkdownExtractor()
        case .pdf: throw ExtractError.unsupported(.pdf)
        }
    }
}

extension Data {
    func decodedText() throws -> String {
        if let s = String(data: self, encoding: .utf8) { return s }
        if let s = String(data: self, encoding: .utf16) { return s }
        throw ExtractError.undecodable
    }
}

enum Paragraphs {
    /// Blank lines separate paragraphs; single line breaks inside one become spaces.
    static func normalize(_ text: String) -> String {
        text.replacingOccurrences(of: "\r\n", with: "\n")
            .components(separatedBy: "\n\n")
            .map { $0.split(separator: "\n").map { $0.trimmingCharacters(in: .whitespaces) }
                .filter { !$0.isEmpty }.joined(separator: " ") }
            .filter { !$0.isEmpty }
            .joined(separator: "\n\n")
    }
}
```

`MarkdownExtractor` is defined in Task 6; until then add a stub in `MarkdownExtractor.swift`:

```swift
import Foundation
public struct MarkdownExtractor: Extractor {
    public init() {}
    public func script(from data: Data, options: ExtractOptions) throws -> Script { .empty }
}
```

`PlainTextExtractor.swift`:

```swift
import Foundation

public struct PlainTextExtractor: Extractor {
    public init() {}
    public func script(from data: Data, options: ExtractOptions) throws -> Script {
        let source = Paragraphs.normalize(try data.decodedText())
        return Script(source: source, sentences: SentenceSplitter.split(source))
    }
}
```

- [ ] **Step 3: Run, commit**

Run: `swift test --filter PlainTextExtractorTests` → PASS.

```bash
git add -A && git commit -m "prose: extractor protocol and plain text"
```

---

### Task 6: Prose: Markdown extractor

**Files:**
- Modify: `Sources/Prose/MarkdownExtractor.swift`
- Create: `Tests/ProseTests/MarkdownExtractorTests.swift`, `Tests/ProseTests/Fixtures/essay.md`

**Interfaces:**
- Consumes: `Extractor`, `Paragraphs.normalize`, `SentenceSplitter`, swift-markdown `Document`, `MarkupWalker`.
- Produces: `MarkdownExtractor` following every rule in the spec's Prose section.

- [ ] **Step 1: Fixture**

`Fixtures/essay.md`:

````markdown
---
title: It's been a fast year
tags: [research]
---

# Pick your own problems

Nobody *really* teaches you **research**. See [Hamming's talk](https://example.com/hamming) for more.

- first item
- second item with `inline code`

![a diagram](diagram.png)

```swift
let x = 1
```

| Name | Country |
|------|---------|
| Samantha | United States |
| Karen | Australia |

> A quoted line.

Final paragraph.
````

- [ ] **Step 2: Failing tests**

```swift
import Foundation
import Testing
@testable import Prose

@Suite struct MarkdownExtractorTests {
    func fixture(_ name: String) throws -> Data {
        try Data(contentsOf: Bundle.module.url(forResource: name, withExtension: nil, subdirectory: "Fixtures")!)
    }
    @Test func readsTheEssayAsProse() throws {
        let s = try MarkdownExtractor().script(from: fixture("essay.md"), options: .default)
        #expect(s.source == """
        Pick your own problems

        Nobody really teaches you research. See Hamming's talk for more.

        first item

        second item with inline code

        Code block.

        Name, Country

        Samantha, United States

        Karen, Australia

        A quoted line.

        Final paragraph.
        """)
    }
    @Test func frontMatterIsDropped() throws {
        let s = try MarkdownExtractor().script(from: fixture("essay.md"), options: .default)
        #expect(!s.source.contains("tags:"))
    }
    @Test func codeIsReadWhenNotSkipped() throws {
        let s = try MarkdownExtractor().script(from: fixture("essay.md"), options: ExtractOptions(skipCode: false))
        #expect(s.source.contains("let x = 1"))
        #expect(!s.source.contains("Code block."))
    }
    @Test func headingIsItsOwnSentence() throws {
        let s = try MarkdownExtractor().script(from: fixture("essay.md"), options: .default)
        #expect(s.sentences.first?.text == "Pick your own problems")
        for sen in s.sentences { #expect(String(s.source[sen.range]) == sen.text) }
    }
    @Test func hardWrappedParagraphJoins() throws {
        let md = "one line\nsecond line of the same paragraph\n\nnext"
        let s = try MarkdownExtractor().script(from: Data(md.utf8), options: .default)
        #expect(s.source == "one line second line of the same paragraph\n\nnext")
    }
}
```

Run: FAIL (stub returns empty).

- [ ] **Step 3: Implement**

```swift
import Foundation
import Markdown

public struct MarkdownExtractor: Extractor {
    public init() {}
    public func script(from data: Data, options: ExtractOptions) throws -> Script {
        let raw = FrontMatter.strip(try data.decodedText())
        let document = Document(parsing: raw)
        var walker = SpeechWalker(skipCode: options.skipCode)
        walker.visit(document)
        let source = Paragraphs.normalize(walker.blocks.joined(separator: "\n\n"))
        return Script(source: source, sentences: SentenceSplitter.split(source))
    }
}

enum FrontMatter {
    /// Drops a leading YAML block fenced by `---` lines.
    static func strip(_ text: String) -> String {
        let lines = text.split(separator: "\n", omittingEmptySubsequences: false)
        guard lines.first?.trimmingCharacters(in: .whitespaces) == "---" else { return text }
        guard let end = lines.dropFirst().firstIndex(where: { $0.trimmingCharacters(in: .whitespaces) == "---" })
        else { return text }
        return lines[(end + 1)...].joined(separator: "\n")
    }
}

/// Collects one spoken block per Markdown block; inline structure is flattened to its text.
struct SpeechWalker: MarkupWalker {
    let skipCode: Bool
    var blocks: [String] = []

    mutating func visitHeading(_ heading: Heading) { blocks.append(Inline.text(of: heading)) }
    mutating func visitParagraph(_ paragraph: Paragraph) { blocks.append(Inline.text(of: paragraph)) }
    mutating func visitCodeBlock(_ codeBlock: CodeBlock) {
        blocks.append(skipCode ? "Code block." : codeBlock.code.trimmingCharacters(in: .newlines))
    }
    mutating func visitHTMLBlock(_ html: HTMLBlock) {}
    mutating func visitThematicBreak(_ thematicBreak: ThematicBreak) {}
    mutating func visitListItem(_ listItem: ListItem) {
        // A list item's paragraphs and nested lists are each their own block; the marker is dropped.
        descendInto(listItem)
    }
    mutating func visitTable(_ table: Table) {
        blocks.append(table.head.cells.map(Inline.text(of:)).joined(separator: ", "))
        for row in table.body.rows {
            blocks.append(row.cells.map(Inline.text(of:)).joined(separator: ", "))
        }
    }
}

enum Inline {
    static func text(of markup: Markup) -> String {
        var out = ""
        for child in markup.children { append(child, to: &out) }
        return out
    }
    static func append(_ m: Markup, to out: inout String) {
        switch m {
        case let t as Text: out += t.string
        case let c as InlineCode: out += c.code
        case is SoftBreak, is LineBreak: out += " "
        case is Image, is InlineHTML: break
        default: for child in m.children { append(child, to: &out) }
        }
    }
}
```

- [ ] **Step 4: Run, commit**

Run: `swift test --filter MarkdownExtractorTests` → PASS. If `Table.Head`/`Table.Body` property names differ in the resolved swift-markdown version, check `.build/checkouts/swift-markdown/Sources/Markdown/Block Nodes/Tables` and adjust; the fixture assertion is the contract, not the property name.

```bash
git add -A && git commit -m "prose: markdown to speech through swift-markdown"
```

---

### Task 7: Prose: extraction cache

**Files:**
- Create: `Sources/Prose/Extraction.swift`, `Tests/ProseTests/ExtractionTests.swift`

**Interfaces:**
- Produces: `public actor Extraction { public init(); public func script(for url: URL, kind: SourceKind, options: ExtractOptions) async throws -> Script; public func invalidate(_ url: URL) }`, cached by `(path, modificationDate, options)`.

- [ ] **Step 1: Failing test**

```swift
import Foundation
import Testing
@testable import Prose

@Suite struct ExtractionTests {
    @Test func cachesUntilTheFileChanges() async throws {
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        let file = dir.appendingPathComponent("a.txt")
        try "first version.".write(to: file, atomically: true, encoding: .utf8)
        let ex = Extraction()
        let a = try await ex.script(for: file, kind: .plainText, options: .default)
        #expect(a.source == "first version.")
        try "second version.".write(to: file, atomically: true, encoding: .utf8)
        try FileManager.default.setAttributes([.modificationDate: Date().addingTimeInterval(5)], ofItemAtPath: file.path)
        let b = try await ex.script(for: file, kind: .plainText, options: .default)
        #expect(b.source == "second version.")
        #expect(await ex.hits == 0)
        _ = try await ex.script(for: file, kind: .plainText, options: .default)
        #expect(await ex.hits == 1)
    }
}
```

- [ ] **Step 2: Implement**

```swift
import Foundation

public actor Extraction {
    struct Key: Hashable { let path: String; let modified: Date; let options: ExtractOptions }
    private var cache: [Key: Script] = [:]
    private(set) var hits = 0

    public init() {}

    public func script(for url: URL, kind: SourceKind, options: ExtractOptions) async throws -> Script {
        let modified = (try url.resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate) ?? .distantPast
        let key = Key(path: url.path, modified: modified, options: options)
        if let hit = cache[key] { hits += 1; return hit }
        let data = try Data(contentsOf: url)
        let script = try Extractors.extractor(for: kind).script(from: data, options: options)
        cache = cache.filter { $0.key.path != url.path }
        cache[key] = script
        return script
    }

    public func invalidate(_ url: URL) { cache = cache.filter { $0.key.path != url.path } }
}
```

- [ ] **Step 3: Run, commit**

Run: `swift test --filter ExtractionTests` → PASS.

```bash
git add -A && git commit -m "prose: extraction cache keyed by path and mtime"
```

---

### Task 8: Vault: documents, titles, scanner

**Files:**
- Create: `Sources/Vault/DocumentType.swift`, `Sources/Vault/Document.swift`, `Sources/Vault/Title.swift`, `Sources/Vault/Scanner.swift`, `Tests/VaultTests/ScannerTests.swift`, `Tests/VaultTests/TitleTests.swift`

**Interfaces:**
- Produces:
  - `public enum DocumentType: Sendable, Hashable { case markdown, plainText, pdf; public init?(url: URL) }` by extension `md`, `markdown`, `txt`, `text`, `pdf`.
  - `public struct Document: Identifiable, Hashable, Sendable { public var id: String { url.path }; public let url: URL; public let title: String; public let preview: String; public let modified: Date; public let type: DocumentType }`
  - `public struct Folder: Identifiable, Hashable, Sendable { public var id: String { url.path }; public let url: URL; public let name: String; public let folders: [Folder]; public let documents: [Document]; public var documentCount: Int }` (count is recursive).
  - `public enum Title { public static func from(text: String, fallback: String) -> String }`
  - `public enum Scanner { public static func scan(root: URL) throws -> Folder }` sorted folders by name, documents by modified descending, dot-files and dot-folders ignored, PDFs titled by filename and previewed empty.

- [ ] **Step 1: Failing tests**

`TitleTests.swift`:

```swift
import Testing
@testable import Vault

@Suite struct TitleTests {
    @Test func firstHeadingWins() {
        #expect(Title.from(text: "---\na: b\n---\n\nintro line\n\n## The Real Title\n", fallback: "f") == "The Real Title")
    }
    @Test func firstLineWhenNoHeading() {
        #expect(Title.from(text: "\n\nIt's been a fast year. Really.\nmore", fallback: "f") == "It's been a fast year. Really.")
    }
    @Test func fallbackWhenEmpty() {
        #expect(Title.from(text: "  \n", fallback: "notes.txt") == "notes.txt")
    }
    @Test func trimsToEighty() {
        let long = String(repeating: "word ", count: 40)
        #expect(Title.from(text: long, fallback: "f").count <= 80)
    }
}
```

`ScannerTests.swift`:

```swift
import Foundation
import Testing
@testable import Vault

@Suite struct ScannerTests {
    func makeTree() throws -> URL {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        let fm = FileManager.default
        try fm.createDirectory(at: root.appendingPathComponent("Essays"), withIntermediateDirectories: true)
        try fm.createDirectory(at: root.appendingPathComponent(".obsidian"), withIntermediateDirectories: true)
        try "# Fast year\n\nbody".write(to: root.appendingPathComponent("a.md"), atomically: true, encoding: .utf8)
        try "plain first line\nmore".write(to: root.appendingPathComponent("b.txt"), atomically: true, encoding: .utf8)
        try "x".write(to: root.appendingPathComponent(".hidden.md"), atomically: true, encoding: .utf8)
        try "x".write(to: root.appendingPathComponent("image.png"), atomically: true, encoding: .utf8)
        try "# Nested".write(to: root.appendingPathComponent("Essays/c.md"), atomically: true, encoding: .utf8)
        try "x".write(to: root.appendingPathComponent(".obsidian/config.md"), atomically: true, encoding: .utf8)
        return root
    }
    @Test func scansSupportedFilesOnly() throws {
        let f = try Scanner.scan(root: try makeTree())
        #expect(Set(f.documents.map(\.title)) == ["Fast year", "plain first line"])
        #expect(f.folders.map(\.name) == ["Essays"])
        #expect(f.folders[0].documents.first?.title == "Nested")
        #expect(f.documentCount == 3)
    }
    @Test func typesByExtension() {
        #expect(DocumentType(url: URL(fileURLWithPath: "/x/a.MD")) == .markdown)
        #expect(DocumentType(url: URL(fileURLWithPath: "/x/a.text")) == .plainText)
        #expect(DocumentType(url: URL(fileURLWithPath: "/x/a.pdf")) == .pdf)
        #expect(DocumentType(url: URL(fileURLWithPath: "/x/a.png")) == nil)
    }
}
```

Run: FAIL.

- [ ] **Step 2: Implement**

`DocumentType.swift`:

```swift
import Foundation

public enum DocumentType: Sendable, Hashable {
    case markdown, plainText, pdf
    public init?(url: URL) {
        switch url.pathExtension.lowercased() {
        case "md", "markdown": self = .markdown
        case "txt", "text": self = .plainText
        case "pdf": self = .pdf
        default: return nil
        }
    }
}
```

`Document.swift`:

```swift
import Foundation

public struct Document: Identifiable, Hashable, Sendable {
    public var id: String { url.path }
    public let url: URL
    public let title: String
    public let preview: String
    public let modified: Date
    public let type: DocumentType
    public init(url: URL, title: String, preview: String, modified: Date, type: DocumentType) {
        self.url = url; self.title = title; self.preview = preview; self.modified = modified; self.type = type
    }
}

public struct Folder: Identifiable, Hashable, Sendable {
    public var id: String { url.path }
    public let url: URL
    public let name: String
    public let folders: [Folder]
    public let documents: [Document]
    public var documentCount: Int { documents.count + folders.reduce(0) { $0 + $1.documentCount } }
    public init(url: URL, name: String, folders: [Folder], documents: [Document]) {
        self.url = url; self.name = name; self.folders = folders; self.documents = documents
    }
}
```

`Title.swift`:

```swift
import Foundation

public enum Title {
    public static let maxLength = 80
    public static func from(text: String, fallback: String) -> String {
        let body = stripFrontMatter(text)
        let lines = body.split(separator: "\n").map { $0.trimmingCharacters(in: .whitespaces) }.filter { !$0.isEmpty }
        if let heading = lines.first(where: { $0.hasPrefix("#") }) {
            return clip(heading.drop(while: { $0 == "#" || $0 == " " }))
        }
        if let first = lines.first { return clip(Substring(first)) }
        return fallback
    }
    static func clip(_ s: Substring) -> String {
        let t = String(s).trimmingCharacters(in: .whitespaces)
        return t.count <= maxLength ? t : String(t.prefix(maxLength - 1)) + "…"
    }
    static func stripFrontMatter(_ text: String) -> String {
        let lines = text.split(separator: "\n", omittingEmptySubsequences: false)
        guard lines.first?.trimmingCharacters(in: .whitespaces) == "---",
              let end = lines.dropFirst().firstIndex(where: { $0.trimmingCharacters(in: .whitespaces) == "---" })
        else { return text }
        return lines[(end + 1)...].joined(separator: "\n")
    }
}
```

`Scanner.swift`:

```swift
import Foundation

public enum Scanner {
    static let previewBytes = 600

    public static func scan(root: URL) throws -> Folder {
        let fm = FileManager.default
        let keys: [URLResourceKey] = [.isDirectoryKey, .contentModificationDateKey, .nameKey]
        let items = try fm.contentsOfDirectory(at: root, includingPropertiesForKeys: keys, options: [.skipsHiddenFiles])
        var folders: [Folder] = []
        var docs: [Document] = []
        for item in items {
            let v = try item.resourceValues(forKeys: Set(keys))
            if v.isDirectory == true {
                folders.append(try scan(root: item))
            } else if let type = DocumentType(url: item) {
                docs.append(document(at: item, type: type, modified: v.contentModificationDate ?? .distantPast))
            }
        }
        return Folder(
            url: root, name: root.lastPathComponent,
            folders: folders.sorted { $0.name.localizedStandardCompare($1.name) == .orderedAscending },
            documents: docs.sorted { $0.modified > $1.modified })
    }

    static func document(at url: URL, type: DocumentType, modified: Date) -> Document {
        guard type != .pdf else {
            return Document(url: url, title: url.deletingPathExtension().lastPathComponent, preview: "", modified: modified, type: .pdf)
        }
        let head = headText(of: url)
        return Document(
            url: url,
            title: Title.from(text: head, fallback: url.deletingPathExtension().lastPathComponent),
            preview: Title.stripFrontMatter(head), modified: modified, type: type)
    }

    static func headText(of url: URL) -> String {
        guard let handle = try? FileHandle(forReadingFrom: url) else { return "" }
        defer { try? handle.close() }
        let data = (try? handle.read(upToCount: previewBytes * 4)) ?? Data()
        return String(decoding: data, as: UTF8.self)
    }
}
```

- [ ] **Step 3: Run, commit**

Run: `swift test --filter VaultTests` → PASS.

```bash
git add -A && git commit -m "vault: document types, titles, scanner"
```

---

### Task 9: Vault: note naming and the Vault actor

**Files:**
- Create: `Sources/Vault/NoteName.swift`, `Sources/Vault/Vault.swift`, `Tests/VaultTests/NoteNameTests.swift`, `Tests/VaultTests/VaultTests.swift`

**Interfaces:**
- Produces:
  - `public enum NoteName { public static func make(from text: String, taken: Set<String>) -> String }` returns a file name with `.md`.
  - `public enum VaultError: Error { case notEditable(DocumentType), noRoots }`
  - `public actor Vault { public init(roots: [URL]); public var roots: [URL]; public func setRoots(_:); public func tree() throws -> [Folder]; public func makeNote(text: String, in folder: URL) throws -> URL; public func save(text: String, to document: Document) throws }`

- [ ] **Step 1: Failing tests**

`NoteNameTests.swift`:

```swift
import Testing
@testable import Vault

@Suite struct NoteNameTests {
    @Test func firstLineBecomesTheName() {
        #expect(NoteName.make(from: "# It's been a fast year.\n\nbody", taken: []) == "It's been a fast year.md")
    }
    @Test func unsafeCharactersDrop() {
        #expect(NoteName.make(from: "a/b:c\\d?e*f", taken: []) == "abcdef.md")
    }
    @Test func clipsToSixty() {
        let name = NoteName.make(from: String(repeating: "x", count: 100), taken: [])
        #expect(name.count == 60 + 3)
    }
    @Test func collisionsCount() {
        #expect(NoteName.make(from: "Note", taken: ["Note.md", "Note 2.md"]) == "Note 3.md")
    }
    @Test func emptyIsNote() {
        #expect(NoteName.make(from: " \n ", taken: []) == "Note.md")
    }
}
```

`VaultTests.swift`:

```swift
import Foundation
import Testing
@testable import Vault

@Suite struct VaultTests {
    func tempRoot() throws -> URL {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        return root
    }
    @Test func makesANoteAndSeesItInTheTree() async throws {
        let root = try tempRoot()
        let vault = Vault(roots: [root])
        let url = try await vault.makeNote(text: "Hello there.\n\nMore.", in: root)
        #expect(url.lastPathComponent == "Hello there..md" || url.lastPathComponent == "Hello there.md")
        let tree = try await vault.tree()
        #expect(tree[0].documents.first?.title == "Hello there.")
    }
    @Test func savesEditsAtomically() async throws {
        let root = try tempRoot()
        let vault = Vault(roots: [root])
        let url = try await vault.makeNote(text: "v1", in: root)
        let doc = try await vault.tree()[0].documents[0]
        try await vault.save(text: "v2", to: doc)
        #expect(try String(contentsOf: url, encoding: .utf8) == "v2")
    }
    @Test func refusesToSavePDF() async throws {
        let root = try tempRoot()
        let vault = Vault(roots: [root])
        let pdf = Document(url: root.appendingPathComponent("x.pdf"), title: "x", preview: "", modified: .now, type: .pdf)
        await #expect(throws: VaultError.self) { try await vault.save(text: "no", to: pdf) }
    }
}
```

Decide the trailing-period rule now: `NoteName` strips trailing periods so the name is `Hello there.md`; tighten the first assertion to that single value.

- [ ] **Step 2: Implement**

`NoteName.swift`:

```swift
import Foundation

public enum NoteName {
    public static let maxLength = 60
    static let unsafe = CharacterSet(charactersIn: "/:\\?*\"<>|").union(.controlCharacters).union(.newlines)

    public static func make(from text: String, taken: Set<String>) -> String {
        let firstLine = text.split(separator: "\n").map { $0.trimmingCharacters(in: .whitespaces) }
            .first { !$0.isEmpty } ?? ""
        var base = firstLine.drop(while: { $0 == "#" || $0 == " " })
            .unicodeScalars.filter { !unsafe.contains($0) }
            .map(String.init).joined()
            .trimmingCharacters(in: .whitespaces)
        while base.hasSuffix(".") { base.removeLast() }
        if base.count > maxLength { base = String(base.prefix(maxLength)) }
        if base.isEmpty { base = "Note" }
        var candidate = base + ".md"
        var n = 2
        while taken.contains(candidate) { candidate = "\(base) \(n).md"; n += 1 }
        return candidate
    }
}
```

`Vault.swift`:

```swift
import Foundation

public enum VaultError: Error, Equatable { case notEditable(DocumentType), noRoots }

public actor Vault {
    public private(set) var roots: [URL]
    public init(roots: [URL]) { self.roots = roots }

    public func setRoots(_ urls: [URL]) { roots = urls }

    public func tree() throws -> [Folder] { try roots.map { try Scanner.scan(root: $0) } }

    public func makeNote(text: String, in folder: URL) throws -> URL {
        let existing = Set((try? FileManager.default.contentsOfDirectory(atPath: folder.path)) ?? [])
        let url = folder.appendingPathComponent(NoteName.make(from: text, taken: existing))
        try text.write(to: url, atomically: true, encoding: .utf8)
        return url
    }

    public func save(text: String, to document: Document) throws {
        guard document.type != .pdf else { throw VaultError.notEditable(document.type) }
        try text.write(to: document.url, atomically: true, encoding: .utf8)
    }
}
```

- [ ] **Step 3: Run, commit**

Run: `swift test --filter VaultTests` → PASS.

```bash
git add -A && git commit -m "vault: note naming and the vault actor"
```

---

### Task 10: Vault: FSEvents watcher

**Files:**
- Create: `Sources/Vault/FolderWatcher.swift`, `Tests/VaultTests/FolderWatcherTests.swift`

**Interfaces:**
- Produces: `public final class FolderWatcher: @unchecked Sendable { public init(paths: [URL], latency: TimeInterval = 0.3, onChange: @escaping @Sendable () -> Void); public func stop() }`. Recursive by nature of FSEvents. One callback per burst.

- [ ] **Step 1: Failing test**

```swift
import Foundation
import Testing
@testable import Vault

@Suite struct FolderWatcherTests {
    @Test func firesOnceForANestedWrite() async throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        let nested = root.appendingPathComponent("deep/er")
        try FileManager.default.createDirectory(at: nested, withIntermediateDirectories: true)
        let fired = Fired()
        let watcher = FolderWatcher(paths: [root], latency: 0.2) { fired.bump() }
        defer { watcher.stop() }
        try await Task.sleep(for: .milliseconds(300))
        try "a".write(to: nested.appendingPathComponent("a.md"), atomically: true, encoding: .utf8)
        try "b".write(to: nested.appendingPathComponent("b.md"), atomically: true, encoding: .utf8)
        try await Task.sleep(for: .seconds(2))
        #expect(fired.count >= 1)
        #expect(fired.count <= 2)
    }
}

final class Fired: @unchecked Sendable {
    private let lock = NSLock()
    private var n = 0
    var count: Int { lock.withLock { n } }
    func bump() { lock.withLock { n += 1 } }
}
```

- [ ] **Step 2: Implement**

```swift
import CoreServices
import Foundation

/// Recursive folder watching through FSEvents. `onChange` is called on a private queue,
/// coalesced by `latency`, once per burst of changes.
public final class FolderWatcher: @unchecked Sendable {
    private var stream: FSEventStreamRef?
    private let queue = DispatchQueue(label: "design.kevxu.aloud.watcher")
    private let onChange: @Sendable () -> Void

    public init(paths: [URL], latency: TimeInterval = 0.3, onChange: @escaping @Sendable () -> Void) {
        self.onChange = onChange
        var context = FSEventStreamContext(
            version: 0, info: Unmanaged.passUnretained(self).toOpaque(),
            retain: nil, release: nil, copyDescription: nil)
        let callback: FSEventStreamCallback = { _, info, _, _, _, _ in
            guard let info else { return }
            Unmanaged<FolderWatcher>.fromOpaque(info).takeUnretainedValue().onChange()
        }
        let flags = UInt32(kFSEventStreamCreateFlagFileEvents | kFSEventStreamCreateFlagNoDefer | kFSEventStreamCreateFlagUseCFTypes)
        guard let s = FSEventStreamCreate(
            nil, callback, &context, paths.map(\.path) as CFArray,
            FSEventStreamEventId(kFSEventStreamEventIdSinceNow), latency, flags)
        else { return }
        stream = s
        FSEventStreamSetDispatchQueue(s, queue)
        FSEventStreamStart(s)
    }

    public func stop() {
        guard let s = stream else { return }
        FSEventStreamStop(s)
        FSEventStreamInvalidate(s)
        FSEventStreamRelease(s)
        stream = nil
    }

    deinit { stop() }
}
```

With `kFSEventStreamCreateFlagFileEvents`, two writes 20 ms apart inside one latency window arrive as one callback; the test allows two in case they straddle a window.

- [ ] **Step 3: Run, commit**

Run: `swift test --filter FolderWatcherTests` → PASS.

```bash
git add -A && git commit -m "vault: recursive folder watcher over FSEvents"
```

---

### Task 11: Vault: progress store

**Files:**
- Create: `Sources/Vault/ProgressStore.swift`, `Tests/VaultTests/ProgressStoreTests.swift`

**Interfaces:**
- Produces:
  - `public struct Progress: Codable, Hashable, Sendable { public var sentenceIndex: Int; public var finished: Bool; public var lastPlayed: Date }`
  - `public final class ProgressStore: @unchecked Sendable { public init(file: URL); public static func standard() -> ProgressStore` (Application Support/Aloud/progress.json)`; public func progress(for url: URL) -> Progress?; public func set(_ p: Progress, for url: URL); public func lastPlayedPath() -> String? }`. Writes are debounced 1 s and flushed on `flush()`.

- [ ] **Step 1: Failing test**

```swift
import Foundation
import Testing
@testable import Vault

@Suite struct ProgressStoreTests {
    @Test func roundTripsThroughDisk() throws {
        let file = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString + ".json")
        let a = ProgressStore(file: file)
        let url = URL(fileURLWithPath: "/tmp/x.md")
        a.set(Progress(sentenceIndex: 12, finished: false, lastPlayed: .now), for: url)
        a.flush()
        let b = ProgressStore(file: file)
        #expect(b.progress(for: url)?.sentenceIndex == 12)
        #expect(b.lastPlayedPath() == "/tmp/x.md")
    }
    @Test func missingFileIsEmpty() {
        let file = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString + ".json")
        #expect(ProgressStore(file: file).progress(for: URL(fileURLWithPath: "/nope")) == nil)
    }
}
```

- [ ] **Step 2: Implement**

```swift
import Foundation

public struct Progress: Codable, Hashable, Sendable {
    public var sentenceIndex: Int
    public var finished: Bool
    public var lastPlayed: Date
    public init(sentenceIndex: Int, finished: Bool, lastPlayed: Date) {
        self.sentenceIndex = sentenceIndex; self.finished = finished; self.lastPlayed = lastPlayed
    }
}

public final class ProgressStore: @unchecked Sendable {
    private let file: URL
    private let lock = NSLock()
    private var table: [String: Progress]
    private var pending: DispatchWorkItem?
    public static let debounce: TimeInterval = 1

    public init(file: URL) {
        self.file = file
        if let data = try? Data(contentsOf: file), let t = try? JSONDecoder().decode([String: Progress].self, from: data) {
            table = t
        } else {
            table = [:]
        }
    }

    public static func standard() -> ProgressStore {
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("Aloud", isDirectory: true)
        try? FileManager.default.createDirectory(at: base, withIntermediateDirectories: true)
        return ProgressStore(file: base.appendingPathComponent("progress.json"))
    }

    public func progress(for url: URL) -> Progress? { lock.withLock { table[url.path] } }

    public func set(_ p: Progress, for url: URL) {
        lock.withLock { table[url.path] = p }
        scheduleWrite()
    }

    public func lastPlayedPath() -> String? {
        lock.withLock { table.max { $0.value.lastPlayed < $1.value.lastPlayed }?.key }
    }

    private func scheduleWrite() {
        pending?.cancel()
        let item = DispatchWorkItem { [weak self] in self?.flush() }
        pending = item
        DispatchQueue.global(qos: .utility).asyncAfter(deadline: .now() + Self.debounce, execute: item)
    }

    public func flush() {
        let snapshot = lock.withLock { table }
        if let data = try? JSONEncoder().encode(snapshot) { try? data.write(to: file, options: .atomic) }
    }
}
```

- [ ] **Step 3: Run, commit**

Run: `swift test --filter ProgressStoreTests` → PASS.

```bash
git add -A && git commit -m "vault: progress store"
```

---

### Task 12: Speech: Voice, Rate, Timeline

**Files:**
- Create: `Sources/Speech/Voice.swift`, `Sources/Speech/Rate.swift`, `Sources/Speech/Timeline.swift`, `Tests/SpeechTests/RateTests.swift`, `Tests/SpeechTests/TimelineTests.swift`

**Interfaces:**
- Produces:
  - `public struct Voice: Identifiable, Hashable, Sendable { public let id: String; public let name: String; public let language: String; public let quality: Quality }`, `public enum Quality: Int, Sendable, Comparable { case standard, enhanced, premium }` with `label`.
  - `public enum Rate: Double, CaseIterable, Sendable { case x075 = 0.75, x1 = 1, x125 = 1.25, x15 = 1.5, x175 = 1.75, x2 = 2, x25 = 2.5, x3 = 3; public var label: String; public var next: Rate; public var appleRate: Float }`.
  - `public struct Timeline: Sendable { public init(script: Script, rate: Rate); public let starts: [Duration]; public let total: Duration; public func index(at: Duration) -> Int; public func elapsed(at index: Int) -> Duration }`.

- [ ] **Step 1: Failing tests**

`RateTests.swift`:

```swift
import Testing
@testable import Speech

@Suite struct RateTests {
    @Test func labelsDropTrailingZeros() {
        #expect(Rate.x1.label == "1x"); #expect(Rate.x125.label == "1.25x"); #expect(Rate.x15.label == "1.5x")
    }
    @Test func cyclesAndWraps() {
        #expect(Rate.x1.next == .x125); #expect(Rate.x3.next == .x075)
    }
    @Test func appleRateIsDefaultAtOneAndMaxAtThree() {
        #expect(Rate.x1.appleRate == 0.5)
        #expect(Rate.x3.appleRate == 1.0)
        #expect(Rate.x075.appleRate == 0.375)
        #expect(Rate.x2.appleRate == 0.75)
    }
    @Test func eightSteps() { #expect(Rate.allCases.count == 8) }
}
```

`TimelineTests.swift`:

```swift
import Prose
import Testing
@testable import Speech

@Suite struct TimelineTests {
    // 160 words per minute at 1x, so each 16-word sentence is 6 seconds.
    let script: Script = {
        let sentence = Array(repeating: "word", count: 16).joined(separator: " ") + "."
        let source = [sentence, sentence, sentence].joined(separator: " ")
        return Script(source: source, sentences: SentenceSplitter.split(source))
    }()
    @Test func startsAccumulate() {
        let t = Timeline(script: script, rate: .x1)
        #expect(t.starts == [.zero, .seconds(6), .seconds(12)])
        #expect(t.total == .seconds(18))
    }
    @Test func indexAtTime() {
        let t = Timeline(script: script, rate: .x1)
        #expect(t.index(at: .seconds(0)) == 0)
        #expect(t.index(at: .seconds(7)) == 1)
        #expect(t.index(at: .seconds(99)) == 2)
        #expect(t.index(at: .seconds(-5)) == 0)
    }
    @Test func rateShrinksIt() {
        #expect(Timeline(script: script, rate: .x2).total == .seconds(9))
    }
}
```

- [ ] **Step 2: Implement**

`Voice.swift`:

```swift
import Foundation

public enum Quality: Int, Sendable, Comparable, Hashable {
    case standard, enhanced, premium
    public var label: String {
        switch self { case .standard: "Default"; case .enhanced: "Enhanced"; case .premium: "Premium" }
    }
    public static func < (a: Quality, b: Quality) -> Bool { a.rawValue < b.rawValue }
}

public struct Voice: Identifiable, Hashable, Sendable {
    public let id: String
    public let name: String
    public let language: String
    public let quality: Quality
    public init(id: String, name: String, language: String, quality: Quality) {
        self.id = id; self.name = name; self.language = language; self.quality = quality
    }
}
```

`Rate.swift`:

```swift
import Foundation

public enum Rate: Double, CaseIterable, Sendable, Hashable {
    case x075 = 0.75, x1 = 1, x125 = 1.25, x15 = 1.5, x175 = 1.75, x2 = 2, x25 = 2.5, x3 = 3

    public var factor: Double { rawValue }

    public var label: String {
        let s = rawValue.formatted(.number.precision(.fractionLength(0...2)))
        return s + "x"
    }

    public var next: Rate {
        let all = Rate.allCases
        let i = all.firstIndex(of: self)!
        return all[(i + 1) % all.count]
    }

    /// AVSpeechUtterance rate: 0.5 is the default and 1.0 the maximum.
    /// Below 1x the mapping is proportional; above it, 1x to 3x spans default to maximum.
    public var appleRate: Float {
        let d = 0.5
        if rawValue <= 1 { return Float(d * rawValue) }
        return Float(d + (1 - d) * (rawValue - 1) / 2)
    }
}
```

`Timeline.swift`:

```swift
import Foundation
import Prose

public struct Timeline: Sendable {
    public let starts: [Duration]
    public let total: Duration

    public init(script: Script, rate: Rate) {
        var acc: Duration = .zero
        var starts: [Duration] = []
        for s in script.sentences {
            starts.append(acc)
            acc += Estimate.duration(words: Estimate.words(in: s.text), factor: rate.factor)
        }
        self.starts = starts
        self.total = acc
    }

    public func index(at time: Duration) -> Int {
        guard !starts.isEmpty else { return 0 }
        if time <= .zero { return 0 }
        var i = starts.count - 1
        while i > 0, starts[i] > time { i -= 1 }
        return i
    }

    public func elapsed(at index: Int) -> Duration {
        guard !starts.isEmpty else { return .zero }
        return starts[min(max(index, 0), starts.count - 1)]
    }
}
```

- [ ] **Step 3: Run, commit**

Run: `swift test --filter SpeechTests` → PASS.

```bash
git add -A && git commit -m "speech: voice, rate steps, timeline"
```

---

### Task 13: Speech: VoiceProvider, fake, Player

**Files:**
- Create: `Sources/Speech/VoiceProvider.swift`, `Sources/Speech/FakeVoiceProvider.swift`, `Sources/Speech/Player.swift`, `Tests/SpeechTests/PlayerTests.swift`

**Interfaces:**
- Produces:
  - `public protocol VoiceProvider: AnyObject, Sendable { var voices: [Voice] { get }; var defaultVoice: Voice? { get }; @MainActor func speak(_ text: String, voice: Voice?, rate: Rate, onWord: @escaping @MainActor (NSRange) -> Void, onFinish: @escaping @MainActor () -> Void); @MainActor func stop() }`
  - `public final class FakeVoiceProvider: VoiceProvider` recording `spoken: [(text: String, rate: Rate)]`, with `@MainActor func finishCurrent()` and `@MainActor func word(_ range: NSRange)`.
  - `@Observable @MainActor public final class Player { public init(provider: any VoiceProvider); public private(set) var script: Script; public private(set) var sentenceIndex: Int; public private(set) var wordRange: Range<String.Index>?; public private(set) var isPlaying: Bool; public private(set) var finished: Bool; public var rate: Rate { didSet }; public var voice: Voice? { didSet }; public var onSentence: ((Int) -> Void)?; public var onFinished: (() -> Void)?; public var timeline: Timeline; public var elapsed: Duration; public var remaining: Duration; public var progress: Double; public func load(_ script: Script, at index: Int); public func play(); public func pause(); public func toggle(); public func seek(to index: Int); public func seek(progress: Double); public func skip(seconds: Double); public static let skipSeconds: Double = 15 }`

- [ ] **Step 1: Failing tests**

```swift
import Foundation
import Prose
import Testing
@testable import Speech

@Suite @MainActor struct PlayerTests {
    func make() -> (Player, FakeVoiceProvider) {
        let fake = FakeVoiceProvider()
        let p = Player(provider: fake)
        let source = "One two three. Four five six. Seven eight nine. Ten eleven twelve."
        p.load(Script(source: source, sentences: SentenceSplitter.split(source)), at: 0)
        return (p, fake)
    }
    @Test func playSpeaksSentenceBySentence() {
        let (p, fake) = make()
        p.play()
        #expect(fake.spoken.map(\.text) == ["One two three."])
        fake.finishCurrent()
        #expect(fake.spoken.map(\.text) == ["One two three.", "Four five six."])
        #expect(p.sentenceIndex == 1)
        #expect(p.isPlaying)
    }
    @Test func finishesAfterTheLastSentence() {
        let (p, fake) = make()
        var done = false
        p.onFinished = { done = true }
        p.seek(to: 3); p.play()
        fake.finishCurrent()
        #expect(done); #expect(!p.isPlaying); #expect(p.finished)
    }
    @Test func rateChangeAppliesAtTheNextSentence() {
        let (p, fake) = make()
        p.play()
        p.rate = .x2
        #expect(fake.spoken.last?.rate == .x1)
        fake.finishCurrent()
        #expect(fake.spoken.last?.rate == .x2)
    }
    @Test func seekWhilePlayingRestartsAtTheTarget() {
        let (p, fake) = make()
        p.play(); p.seek(to: 2)
        #expect(fake.stops == 1)
        #expect(fake.spoken.last?.text == "Seven eight nine.")
        #expect(p.isPlaying)
    }
    @Test func skipLandsOnASentenceBoundary() {
        let (p, _) = make()
        // each 3-word sentence is 1.125 s at 1x; 15 s forward from 0 clamps to the last sentence
        p.skip(seconds: 15)
        #expect(p.sentenceIndex == 3)
        p.skip(seconds: -15)
        #expect(p.sentenceIndex == 0)
    }
    @Test func wordRangeMapsIntoTheSource() {
        let (p, fake) = make()
        p.play()
        fake.word(NSRange(location: 4, length: 3))
        #expect(String(p.script.source[p.wordRange!]) == "two")
    }
    @Test func pauseStopsAndKeepsIndex() {
        let (p, fake) = make()
        p.play(); fake.finishCurrent(); p.pause()
        #expect(!p.isPlaying); #expect(p.sentenceIndex == 1); #expect(fake.stops == 1)
    }
    @Test func progressIsATimelineFraction() {
        let (p, _) = make()
        p.seek(to: 2)
        #expect(abs(p.progress - 0.5) < 0.001)
        p.seek(progress: 0.9)
        #expect(p.sentenceIndex == 3)
    }
}
```

- [ ] **Step 2: Implement**

`VoiceProvider.swift`:

```swift
import Foundation

public protocol VoiceProvider: AnyObject, Sendable {
    var voices: [Voice] { get }
    var defaultVoice: Voice? { get }
    @MainActor func speak(
        _ text: String, voice: Voice?, rate: Rate,
        onWord: @escaping @MainActor (NSRange) -> Void,
        onFinish: @escaping @MainActor () -> Void)
    @MainActor func stop()
}
```

`FakeVoiceProvider.swift`:

```swift
import Foundation

/// Records what it was asked to speak and lets a test drive the callbacks.
/// Shipped in the module so the app can run silent with `--silent`.
@MainActor
public final class FakeVoiceProvider: VoiceProvider {
    public struct Request: Sendable { public let text: String; public let rate: Rate; public let voice: Voice? }
    public private(set) var spoken: [Request] = []
    public private(set) var stops = 0
    private var onWord: (@MainActor (NSRange) -> Void)?
    private var onFinish: (@MainActor () -> Void)?

    public nonisolated init() {}

    public nonisolated var voices: [Voice] { [Voice(id: "fake", name: "Fake", language: "en-US", quality: .standard)] }
    public nonisolated var defaultVoice: Voice? { voices.first }

    public func speak(
        _ text: String, voice: Voice?, rate: Rate,
        onWord: @escaping @MainActor (NSRange) -> Void, onFinish: @escaping @MainActor () -> Void
    ) {
        spoken.append(Request(text: text, rate: rate, voice: voice))
        self.onWord = onWord; self.onFinish = onFinish
    }

    public func stop() { stops += 1; onWord = nil; onFinish = nil }

    public func finishCurrent() { let f = onFinish; onFinish = nil; onWord = nil; f?() }
    public func word(_ range: NSRange) { onWord?(range) }
}
```

`Player.swift`:

```swift
import Foundation
import Observation
import Prose

@Observable @MainActor
public final class Player {
    public static let skipSeconds: Double = 15

    public private(set) var script: Script = .empty
    public private(set) var sentenceIndex = 0
    public private(set) var wordRange: Range<String.Index>?
    public private(set) var isPlaying = false
    public private(set) var finished = false
    public private(set) var timeline: Timeline

    public var rate: Rate = .x1 { didSet { timeline = Timeline(script: script, rate: rate) } }
    public var voice: Voice?

    public var onSentence: ((Int) -> Void)?
    public var onFinished: (() -> Void)?

    private let provider: any VoiceProvider
    private var generation = 0

    public init(provider: any VoiceProvider) {
        self.provider = provider
        self.voice = provider.defaultVoice
        self.timeline = Timeline(script: .empty, rate: .x1)
    }

    public var elapsed: Duration { timeline.elapsed(at: sentenceIndex) }
    public var remaining: Duration { timeline.total - elapsed }
    public var progress: Double {
        timeline.total == .zero ? 0 : elapsed / timeline.total
    }

    public func load(_ script: Script, at index: Int) {
        stopSpeaking()
        self.script = script
        timeline = Timeline(script: script, rate: rate)
        sentenceIndex = min(max(index, 0), max(script.sentences.count - 1, 0))
        finished = false
        wordRange = nil
    }

    public func play() {
        guard !script.sentences.isEmpty else { return }
        if finished { sentenceIndex = 0; finished = false }
        isPlaying = true
        speakCurrent()
    }

    public func pause() {
        stopSpeaking()
        isPlaying = false
    }

    public func toggle() { isPlaying ? pause() : play() }

    public func seek(to index: Int) {
        let wasPlaying = isPlaying
        stopSpeaking()
        sentenceIndex = min(max(index, 0), max(script.sentences.count - 1, 0))
        finished = false
        wordRange = nil
        onSentence?(sentenceIndex)
        if wasPlaying { speakCurrent() }
    }

    public func seek(progress: Double) {
        seek(to: timeline.index(at: timeline.total * min(max(progress, 0), 1)))
    }

    public func skip(seconds: Double) {
        seek(to: timeline.index(at: elapsed + .seconds(seconds)))
    }

    private func speakCurrent() {
        guard sentenceIndex < script.sentences.count else { return }
        generation += 1
        let gen = generation
        let sentence = script.sentences[sentenceIndex]
        provider.speak(
            sentence.text, voice: voice, rate: rate,
            onWord: { [weak self] ns in
                guard let self, gen == self.generation else { return }
                if let r = Range(ns, in: sentence.text) {
                    let lo = self.script.source.index(sentence.range.lowerBound, offsetBy: sentence.text.distance(from: sentence.text.startIndex, to: r.lowerBound))
                    let hi = self.script.source.index(lo, offsetBy: sentence.text.distance(from: r.lowerBound, to: r.upperBound))
                    self.wordRange = lo..<hi
                }
            },
            onFinish: { [weak self] in
                guard let self, gen == self.generation else { return }
                self.advance()
            })
    }

    private func advance() {
        let next = sentenceIndex + 1
        if next < script.sentences.count {
            sentenceIndex = next
            wordRange = nil
            onSentence?(next)
            speakCurrent()
        } else {
            isPlaying = false
            finished = true
            wordRange = nil
            onFinished?()
        }
    }

    private func stopSpeaking() {
        generation += 1
        provider.stop()
    }
}
```

`Duration / Duration` and `Duration * Double` exist in Swift's `Duration`; if the toolchain rejects `timeline.total * x`, compute through `.components` seconds as a `Double` helper in `Timeline` (`var seconds: Double`).

- [ ] **Step 3: Run, commit**

Run: `swift test --filter PlayerTests` → PASS.

```bash
git add -A && git commit -m "speech: player over a voice provider, with a fake"
```

---

### Task 14: Speech: Apple provider and `--say`

**Files:**
- Create: `Sources/Speech/AppleVoiceProvider.swift`
- Modify: `Sources/Aloud/AloudApp.swift`

**Interfaces:**
- Produces: `public final class AppleVoiceProvider: VoiceProvider` over `AVSpeechSynthesizer`, voices grouped later by `language`; `aloud --say <file>` speaks a file from the terminal and exits at the end.

- [ ] **Step 1: Implement the provider**

```swift
import AVFoundation
import Foundation

@MainActor
public final class AppleVoiceProvider: NSObject, VoiceProvider, AVSpeechSynthesizerDelegate {
    private let synth = AVSpeechSynthesizer()
    private var onWord: (@MainActor (NSRange) -> Void)?
    private var onFinish: (@MainActor () -> Void)?

    public override nonisolated init() {
        super.init()
        Task { @MainActor in self.synth.delegate = self }
    }

    public nonisolated var voices: [Voice] {
        AVSpeechSynthesisVoice.speechVoices().map {
            Voice(id: $0.identifier, name: $0.name, language: $0.language, quality: Quality(apple: $0.quality))
        }
    }

    public nonisolated var defaultVoice: Voice? {
        let lang = AVSpeechSynthesisVoice.currentLanguageCode()
        let candidates = voices.filter { $0.language == lang }
        return candidates.max { $0.quality < $1.quality } ?? voices.first
    }

    public func speak(
        _ text: String, voice: Voice?, rate: Rate,
        onWord: @escaping @MainActor (NSRange) -> Void, onFinish: @escaping @MainActor () -> Void
    ) {
        let u = AVSpeechUtterance(string: text)
        u.rate = rate.appleRate
        if let id = voice?.id { u.voice = AVSpeechSynthesisVoice(identifier: id) }
        self.onWord = onWord; self.onFinish = onFinish
        synth.speak(u)
    }

    public func stop() {
        onWord = nil; onFinish = nil
        synth.stopSpeaking(at: .immediate)
    }

    public nonisolated func speechSynthesizer(
        _ s: AVSpeechSynthesizer, willSpeakRangeOfSpeechString r: NSRange, utterance: AVSpeechUtterance
    ) {
        Task { @MainActor in self.onWord?(r) }
    }

    public nonisolated func speechSynthesizer(_ s: AVSpeechSynthesizer, didFinish utterance: AVSpeechUtterance) {
        Task { @MainActor in
            let f = self.onFinish
            self.onFinish = nil; self.onWord = nil
            f?()
        }
    }
}

extension Quality {
    init(apple q: AVSpeechSynthesisVoiceQuality) {
        switch q {
        case .premium: self = .premium
        case .enhanced: self = .enhanced
        default: self = .standard
        }
    }
}
```

If the compiler rejects `nonisolated init` on a `@MainActor` `NSObject` subclass, drop `@MainActor` from the class, mark `speak`/`stop` `@MainActor`, and keep the delegate methods hopping to the main actor as written.

- [ ] **Step 2: `--say` harness in the app**

Replace `AloudApp.swift`:

```swift
import AloudUI
import AppKit
import Prose
import Speech
import SwiftUI
import Vault

@main
struct AloudApp: App {
    static let args = CommandLine.arguments
    static let showGallery = args.contains("--gallery")
    static var sayFile: URL? {
        guard let i = args.firstIndex(of: "--say"), i + 1 < args.count else { return nil }
        return URL(fileURLWithPath: args[i + 1])
    }

    init() {
        if let file = Self.sayFile { Task { @MainActor in try? await Self.say(file) } }
    }

    var body: some Scene {
        WindowGroup("Aloud") {
            if Self.showGallery { Gallery() } else { Text("Aloud") }
        }
        .defaultSize(Size.minWindow)
    }

    @MainActor static func say(_ file: URL) async throws {
        let kind: SourceKind = DocumentType(url: file) == .markdown ? .markdown : .plainText
        let script = try await Extraction().script(for: file, kind: kind, options: .default)
        let player = Player(provider: AppleVoiceProvider())
        player.load(script, at: 0)
        player.onSentence = { print(script.sentences[$0].text) }
        player.onFinished = { NSApp.terminate(nil) }
        player.play()
        withExtendedLifetime(player) {}
        _ = Unmanaged.passRetained(player)
    }
}
```

- [ ] **Step 3: Hear it**

Run: `make build bundle && .build/Aloud.app/Contents/MacOS/Aloud --say Tests/ProseTests/Fixtures/essay.md`
Expected: the essay is spoken sentence by sentence, each printed as it starts, and the process exits after "Final paragraph."

- [ ] **Step 4: Check, commit**

Run: `make check && make test`.

```bash
git add -A && git commit -m "speech: apple voices, and aloud --say"
```

---

### Task 15: App: model, roots, route, shell

**Files:**
- Create: `Sources/Aloud/AppModel.swift`, `Sources/Aloud/RootStore.swift`, `Sources/Aloud/Route.swift`, `Sources/Aloud/RootView.swift`
- Modify: `Sources/Aloud/AloudApp.swift`

**Interfaces:**
- Produces:
  - `enum Route: Hashable { case folder(Folder); case reader(Document) }`
  - `final class RootStore` with `func load() -> [URL]`, `func add(_ url: URL)`, `func remove(_ url: URL)`; bookmarks with `.withSecurityScope` in `UserDefaults` key `vaultRoots`; resolved URLs have `startAccessingSecurityScopedResource()` called once.
  - `@Observable @MainActor final class AppModel { let vault: Vault; let player: Player; let progress: ProgressStore; let extraction: Extraction; var roots: [URL]; var tree: [Folder]; var path: [Route]; var current: Document?; var notice: String?; func start(); func addRoot(_:); func pickRootFolder(); func open(_ doc: Document); func refresh() async; func status(for doc: Document) -> String }`.

- [ ] **Step 1: Route and RootStore**

`Route.swift`:

```swift
import Vault

enum Route: Hashable {
    case folder(Folder)
    case reader(Document)
}
```

`RootStore.swift`:

```swift
import Foundation

final class RootStore {
    static let key = "vaultRoots"
    private let defaults: UserDefaults
    init(defaults: UserDefaults = .standard) { self.defaults = defaults }

    func load() -> [URL] {
        let blobs = defaults.array(forKey: Self.key) as? [Data] ?? []
        return blobs.compactMap { data in
            var stale = false
            guard let url = try? URL(resolvingBookmarkData: data, options: .withSecurityScope, bookmarkDataIsStale: &stale)
            else { return nil }
            _ = url.startAccessingSecurityScopedResource()
            return url
        }
    }

    func add(_ url: URL) {
        guard let data = try? url.bookmarkData(options: .withSecurityScope, includingResourceValuesForKeys: nil, relativeTo: nil)
        else { return }
        var blobs = defaults.array(forKey: Self.key) as? [Data] ?? []
        blobs.append(data)
        defaults.set(blobs, forKey: Self.key)
    }

    func remove(_ url: URL) {
        let keep = load().filter { $0 != url }
        defaults.removeObject(forKey: Self.key)
        keep.forEach(add)
    }
}
```

- [ ] **Step 2: AppModel**

```swift
import AppKit
import Foundation
import Observation
import Prose
import Speech
import Vault

@Observable @MainActor
final class AppModel {
    let vault: Vault
    let player: Player
    let progress: ProgressStore
    let extraction = Extraction()
    private let rootStore = RootStore()
    private var watcher: FolderWatcher?

    var roots: [URL] = []
    var tree: [Folder] = []
    var path: [Route] = []
    var current: Document?
    var notice: String?

    init(provider: any VoiceProvider, progress: ProgressStore = .standard()) {
        self.player = Player(provider: provider)
        self.progress = progress
        self.roots = rootStore.load()
        self.vault = Vault(roots: roots)
        player.onSentence = { [weak self] i in self?.record(index: i, finished: false) }
        player.onFinished = { [weak self] in
            guard let self, let c = self.current else { return }
            self.record(index: self.player.sentenceIndex, finished: true)
            _ = c
        }
    }

    func start() {
        Task { await refresh() }
        watch()
        Task { await restoreLast() }
    }

    func addRoot(_ url: URL) {
        rootStore.add(url)
        roots = rootStore.load()
        Task { await vault.setRoots(roots); await refresh(); watch() }
    }

    func pickRootFolder() {
        let panel = NSOpenPanel()
        panel.canChooseDirectories = true
        panel.canChooseFiles = false
        panel.allowsMultipleSelection = false
        panel.prompt = "Read from this folder"
        if panel.runModal() == .OK, let url = panel.url { addRoot(url) }
    }

    func refresh() async {
        do { tree = try await vault.tree() } catch { notice = "Could not read a vault folder: \(error.localizedDescription)" }
    }

    func open(_ doc: Document) {
        Task {
            do {
                let kind: SourceKind = doc.type == .markdown ? .markdown : .plainText
                let script = try await extraction.script(for: doc.url, kind: kind, options: .default)
                let p = progress.progress(for: doc.url)
                current = doc
                player.load(script, at: p?.finished == true ? 0 : (p?.sentenceIndex ?? 0))
                if path.last != .reader(doc) { path.append(.reader(doc)) }
            } catch {
                notice = "Could not read \(doc.title): \(error.localizedDescription)"
            }
        }
    }

    func status(for doc: Document) -> String {
        if let p = progress.progress(for: doc.url) {
            if p.finished { return "Finished" }
            if p.sentenceIndex > 0, doc.id == current?.id {
                return Format.clock(player.remaining) + " left"
            }
            if p.sentenceIndex > 0 { return "In progress" }
        }
        let words = Estimate.words(in: doc.preview)
        return words == 0 ? "" : "~" + Format.minutes(Estimate.duration(words: words, factor: player.rate.factor))
    }

    private func record(index: Int, finished: Bool) {
        guard let c = current else { return }
        progress.set(Progress(sentenceIndex: index, finished: finished, lastPlayed: .now), for: c.url)
    }

    private func watch() {
        watcher?.stop()
        guard !roots.isEmpty else { return }
        watcher = FolderWatcher(paths: roots) { [weak self] in
            Task { @MainActor in await self?.refresh() }
        }
    }

    private func restoreLast() async {
        guard let path = progress.lastPlayedPath() else { return }
        let url = URL(fileURLWithPath: path)
        guard FileManager.default.fileExists(atPath: path), let type = DocumentType(url: url), type != .pdf else { return }
        let kind: SourceKind = type == .markdown ? .markdown : .plainText
        if let script = try? await extraction.script(for: url, kind: kind, options: .default) {
            let doc = Document(url: url, title: Title.from(text: script.source, fallback: url.lastPathComponent),
                               preview: "", modified: .now, type: type)
            current = doc
            player.load(script, at: progress.progress(for: url)?.sentenceIndex ?? 0)
        }
    }
}

enum Format {
    static func clock(_ d: Duration) -> String {
        let total = Int(d.components.seconds)
        return "\(total / 60):" + String(format: "%02d", total % 60)
    }
    static func minutes(_ d: Duration) -> String {
        let m = max(1, Int((Double(d.components.seconds) / 60).rounded()))
        return m == 1 ? "1 min" : "\(m) min"
    }
}
```

The card estimate uses the 600-byte preview as a proxy for length, which is wrong for long files.
Fix it in this task: extend `Scanner.document(at:)` in `Sources/Vault/Scanner.swift` to add `public let bytes: Int` on `Document` (from `.fileSizeKey`) and estimate words as `bytes / 6` when the preview is shorter than the file.
Add the `bytes` parameter to the `Document` initializer and to every call site in `VaultTests`.

- [ ] **Step 3: RootView and app wiring**

`RootView.swift`:

```swift
import AloudUI
import SwiftUI
import Vault

struct RootView: View {
    @Bindable var model: AppModel

    var body: some View {
        NavigationStack(path: $model.path) {
            LibraryView(model: model, folder: nil)
                .navigationDestination(for: Route.self) { route in
                    switch route {
                    case .folder(let f): LibraryView(model: model, folder: f)
                    case .reader(let d): ReaderView(model: model, document: d)
                    }
                }
        }
        .safeAreaInset(edge: .bottom) {
            if model.current != nil {
                TransportBarView(model: model).padding(Space.l)
            }
        }
        .overlay(alignment: .top) {
            if let n = model.notice {
                Notice(n).padding(Space.l).onTapGesture { model.notice = nil }
            }
        }
        .frame(minWidth: Size.minWindow.width, minHeight: Size.minWindow.height)
        .task { model.start() }
    }
}
```

`LibraryView`, `ReaderView` and `TransportBarView` are Tasks 16 to 18; create placeholder structs now so the target builds:

```swift
// LibraryView.swift, ReaderView.swift, TransportBarView.swift, each:
import SwiftUI
import Vault
struct LibraryView: View { var model: AppModel; var folder: Folder?; var body: some View { Text("Library") } }
struct ReaderView: View { var model: AppModel; var document: Document; var body: some View { Text(document.title) } }
struct TransportBarView: View { var model: AppModel; var body: some View { Text("Transport") } }
```

In `AloudApp.swift` replace the `WindowGroup` body:

```swift
    @State private var model = AppModel(
        provider: args.contains("--silent") ? FakeVoiceProvider() : AppleVoiceProvider())

    var body: some Scene {
        WindowGroup("Aloud") {
            if Self.showGallery { Gallery() } else { RootView(model: model) }
        }
        .defaultSize(Size.minWindow)
    }
```

- [ ] **Step 4: Build and run**

Run: `make check && make test && make dev`
Expected: the window opens showing "Library" (placeholder), no crash, no literal-lint failures.

- [ ] **Step 5: Commit**

```bash
git add -A && git commit -m "app: model, vault roots, route, shell"
```

---

### Task 16: App: library grid

**Files:**
- Modify: `Sources/Aloud/LibraryView.swift`

**Interfaces:**
- Consumes: `AppModel.tree`, `AppModel.status(for:)`, `AppModel.open(_:)`, `AppModel.pickRootFolder()`, `Card`, `FolderCard`, `EmptyState`, `IconButton`.

- [ ] **Step 1: Implement**

```swift
import AloudUI
import SwiftUI
import Vault

struct LibraryView: View {
    var model: AppModel
    var folder: Folder?

    var folders: [Folder] { folder?.folders ?? model.tree.flatMap { $0.folders } }
    var documents: [Document] {
        (folder?.documents ?? model.tree.flatMap { $0.documents }).sorted { $0.modified > $1.modified }
    }
    var title: String { folder?.name ?? "Aloud" }

    var body: some View {
        Group {
            if model.roots.isEmpty {
                EmptyState(onPickFolder: model.pickRootFolder, onPaste: {})
            } else {
                ScrollView {
                    LazyVGrid(columns: [GridItem(.adaptive(minimum: Size.cardWidth), spacing: Space.xl)],
                              alignment: .leading, spacing: Space.xxl) {
                        ForEach(folders) { f in
                            Button { model.path.append(.folder(f)) } label: {
                                FolderCard(name: f.name, count: f.documentCount)
                            }.buttonStyle(.plain)
                        }
                        ForEach(documents) { d in
                            Button { model.open(d) } label: {
                                Card(title: d.title, preview: d.preview, status: model.status(for: d))
                            }.buttonStyle(.plain)
                        }
                    }
                    .padding(Space.xxl)
                }
            }
        }
        .navigationTitle(title)
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                IconButton("folder.badge.plus", label: "Add vault folder", action: model.pickRootFolder)
            }
        }
    }
}
```

The `Card` in `AloudUI` is what the spec's `.chip`-style rules would call a surface; the corner comes from `.rect(cornerRadius: Radius.s)` there, which is fine on macOS where the system draws the curve.

- [ ] **Step 2: Run and look**

Run: `make dev`, pick a folder with some `.md` files.
Expected: folders then documents, newest first, thumbnails legible as blocks of tiny text, `~N min` under each. Click a folder, it pushes; the back button appears in the toolbar. Resize the window: columns reflow, cards stay 160 wide.

- [ ] **Step 3: Commit**

```bash
git add -A && git commit -m "app: library grid"
```

---

### Task 17: App: reader with highlight and seek

**Files:**
- Create: `Sources/Aloud/ReaderTextView.swift`
- Modify: `Sources/Aloud/ReaderView.swift`

**Interfaces:**
- Produces: `struct ReaderTextView: NSViewRepresentable` with `text: String`, `fontSize: CGFloat`, `sentence: NSRange?`, `word: NSRange?`, `follow: Bool`, `editable: Bool`, `onClick: (Int) -> Void` (character offset), `onEdit: (String) -> Void`, `onUserScroll: () -> Void`.
- Consumes: `Player.sentenceIndex`, `Player.wordRange`, `Player.seek(to:)`, `Ink.nsHighlightSentence`, `Ink.nsHighlightWord`, `Type.readerSizes`.

- [ ] **Step 1: The text view**

```swift
import AloudUI
import AppKit
import SwiftUI

struct ReaderTextView: NSViewRepresentable {
    var text: String
    var fontSize: CGFloat
    var sentence: NSRange?
    var word: NSRange?
    var follow: Bool
    var editable: Bool
    var onClick: (Int) -> Void
    var onEdit: (String) -> Void
    var onUserScroll: () -> Void

    func makeCoordinator() -> Coordinator { Coordinator(self) }

    func makeNSView(context: Context) -> NSScrollView {
        let scroll = NSTextView.scrollableTextView()
        let tv = scroll.documentView as! ClickableTextView
        tv.isEditable = false
        tv.isSelectable = false
        tv.isRichText = false
        tv.drawsBackground = false
        tv.textContainerInset = NSSize(width: Space.xxl, height: Space.xxl)
        tv.coordinator = context.coordinator
        scroll.drawsBackground = false
        scroll.hasVerticalScroller = true
        NotificationCenter.default.addObserver(
            context.coordinator, selector: #selector(Coordinator.scrolled), name: NSScrollView.willStartLiveScrollNotification, object: scroll)
        tv.delegate = context.coordinator
        return scroll
    }

    func updateNSView(_ scroll: NSScrollView, context: Context) {
        let tv = scroll.documentView as! ClickableTextView
        context.coordinator.parent = self
        if tv.string != text { tv.string = text }
        let paragraph = NSMutableParagraphStyle()
        paragraph.lineHeightMultiple = Type.readerLineHeightMultiple
        paragraph.paragraphSpacing = fontSize
        tv.typingAttributes = [.font: NSFont.systemFont(ofSize: fontSize), .paragraphStyle: paragraph, .foregroundColor: NSColor.labelColor]
        if tv.font?.pointSize != fontSize {
            tv.textStorage?.setAttributes(tv.typingAttributes, range: NSRange(location: 0, length: (text as NSString).length))
        }
        tv.isEditable = editable
        tv.isSelectable = editable
        guard let lm = tv.layoutManager else { return }
        let all = NSRange(location: 0, length: (text as NSString).length)
        lm.removeTemporaryAttribute(.backgroundColor, forCharacterRange: all)
        if let s = sentence, !editable {
            lm.addTemporaryAttribute(.backgroundColor, value: Ink.nsHighlightSentence, forCharacterRange: s)
            if let w = word { lm.addTemporaryAttribute(.backgroundColor, value: Ink.nsHighlightWord, forCharacterRange: w) }
            if follow, s != context.coordinator.lastScrolledTo {
                context.coordinator.lastScrolledTo = s
                context.coordinator.programmatic = true
                let glyphs = lm.glyphRange(forCharacterRange: s, actualCharacterRange: nil)
                var rect = lm.boundingRect(forGlyphRange: glyphs, in: tv.textContainer!)
                rect.origin.y += tv.textContainerInset.height
                let target = max(0, rect.minY - scroll.contentView.bounds.height / 3)
                NSAnimationContext.runAnimationGroup { ctx in
                    ctx.duration = Motion.normal
                    scroll.contentView.animator().setBoundsOrigin(NSPoint(x: 0, y: target))
                } completionHandler: { context.coordinator.programmatic = false }
            }
        }
    }

    final class Coordinator: NSObject, NSTextViewDelegate {
        var parent: ReaderTextView
        var lastScrolledTo: NSRange?
        var programmatic = false
        init(_ p: ReaderTextView) { parent = p }
        @objc func scrolled() { if !programmatic { parent.onUserScroll() } }
        func textDidChange(_ n: Notification) {
            guard let tv = n.object as? NSTextView else { return }
            parent.onEdit(tv.string)
        }
    }
}

final class ClickableTextView: NSTextView {
    weak var coordinator: ReaderTextView.Coordinator?
    override func mouseDown(with event: NSEvent) {
        guard !isEditable else { return super.mouseDown(with: event) }
        let point = convert(event.locationInWindow, from: nil)
        let index = characterIndexForInsertion(at: point)
        coordinator?.parent.onClick(index)
    }
}
```

`NSTextView.scrollableTextView()` returns a plain `NSTextView`; to get `ClickableTextView`, build the pair by hand instead:

```swift
let scroll = NSScrollView()
let tv = ClickableTextView(frame: .zero)
tv.autoresizingMask = [.width]
tv.isVerticallyResizable = true
tv.isHorizontallyResizable = false
tv.textContainer?.widthTracksTextView = true
scroll.documentView = tv
```

Use this form in `makeNSView`; the `as! ClickableTextView` casts then hold.

- [ ] **Step 2: ReaderView**

```swift
import AloudUI
import Prose
import SwiftUI
import Vault

struct ReaderView: View {
    var model: AppModel
    var document: Document
    @AppStorage("readerSizeIndex") private var sizeIndex = Type.readerDefaultIndex
    @State private var follow = true
    @State private var editing = false
    @State private var draft = ""

    var player: Player { model.player }
    var isCurrent: Bool { model.current?.id == document.id }

    var body: some View {
        HStack {
            Spacer(minLength: 0)
            ReaderTextView(
                text: editing ? draft : player.script.source,
                fontSize: Type.readerSizes[sizeIndex],
                sentence: isCurrent ? nsRange(player.script.sentences[safe: player.sentenceIndex]?.range) : nil,
                word: isCurrent ? nsRange(player.wordRange) : nil,
                follow: follow && player.isPlaying,
                editable: editing,
                onClick: { offset in
                    guard let i = sentenceIndex(at: offset) else { return }
                    follow = true
                    player.seek(to: i)
                    if !player.isPlaying { player.play() }
                },
                onEdit: { draft = $0 },
                onUserScroll: { follow = false })
            .frame(maxWidth: Size.readerMeasure + Space.xxl * 2)
            Spacer(minLength: 0)
        }
        .navigationTitle(document.title)
        .toolbar {
            ToolbarItemGroup(placement: .primaryAction) {
                IconButton("textformat.size.smaller", label: "Smaller text") { sizeIndex = max(0, sizeIndex - 1) }
                IconButton("textformat.size.larger", label: "Larger text") { sizeIndex = min(Type.readerSizes.count - 1, sizeIndex + 1) }
                IconButton(editing ? "checkmark" : "pencil", label: editing ? "Done editing" : "Edit") { toggleEdit() }
                    .disabled(document.type == .pdf)
                IconButton("bookmark", label: "Mark finished") { model.toggleFinished(document) }
            }
        }
        .onChange(of: player.isPlaying) { _, playing in if playing { follow = true } }
    }

    func nsRange(_ r: Range<String.Index>?) -> NSRange? {
        guard let r else { return nil }
        return NSRange(r, in: player.script.source)
    }

    func sentenceIndex(at offset: Int) -> Int? {
        let src = player.script.source
        guard let idx = Range(NSRange(location: offset, length: 0), in: src)?.lowerBound else { return nil }
        return player.script.sentences.lastIndex { $0.range.lowerBound <= idx }
    }

    func toggleEdit() {
        if editing {
            editing = false
            model.saveEdit(draft, to: document)
        } else {
            player.pause()
            draft = player.script.source
            editing = true
        }
    }
}

extension Array {
    subscript(safe i: Int) -> Element? { indices.contains(i) ? self[i] : nil }
}
```

Add to `AppModel`:

```swift
    func toggleFinished(_ doc: Document) {
        let p = progress.progress(for: doc.url)
        progress.set(Progress(sentenceIndex: p?.sentenceIndex ?? 0, finished: !(p?.finished ?? false), lastPlayed: .now), for: doc.url)
    }

    func saveEdit(_ text: String, to doc: Document) {
        Task {
            do {
                try await vault.save(text: text, to: doc)
                await extraction.invalidate(doc.url)
                open(doc)
            } catch { notice = "Could not save \(doc.title): \(error.localizedDescription)" }
        }
    }
```

Editing writes the *prose* back, not the original Markdown, which destroys formatting.
Restrict Edit to `.plainText` documents in this plan (`.disabled(document.type != .plainText)`) and note in the spec that Markdown editing edits the raw file; that lands in plan 2 with a raw-source mode.

- [ ] **Step 3: Run and look**

Run: `make dev`, open a document, click a sentence.
Expected: highlight lands on the clicked sentence, playback starts there, word highlight moves inside it, the view follows in the upper third, scrolling by hand stops the follow, pressing play resumes it. A/A steps through five sizes and persists across relaunch.

- [ ] **Step 4: Check, commit**

Run: `make check && make test`.

```bash
git add -A && git commit -m "app: reader with sentence and word highlight, click to seek"
```

---

### Task 18: App: transport bar and keys

**Files:**
- Modify: `Sources/Aloud/TransportBarView.swift`, `Sources/Aloud/AloudApp.swift`

**Interfaces:**
- Consumes: `GlassBar`, `Scrubber`, `TransportButton`, `RateButton`, `Player`, `Format`.

- [ ] **Step 1: Implement**

```swift
import AloudUI
import Speech
import SwiftUI

struct TransportBarView: View {
    var model: AppModel
    var player: Player { model.player }

    var body: some View {
        VStack(spacing: Space.s) {
            Scrubber(
                progress: player.progress,
                elapsed: Format.clock(player.elapsed),
                remaining: "~" + Format.clock(player.remaining),
                onSeek: { player.seek(progress: $0) })
            HStack {
                RateButton(
                    label: player.rate.label, all: Rate.allCases.map(\.label),
                    onCycle: { player.rate = player.rate.next },
                    onPick: { player.rate = Rate.allCases[$0] })
                Spacer()
                HStack(spacing: Space.xl) {
                    TransportButton(.back15) { player.skip(seconds: -Player.skipSeconds) }
                    TransportButton(player.isPlaying ? .pause : .play) { player.toggle() }
                    TransportButton(.forward15) { player.skip(seconds: Player.skipSeconds) }
                }
                Spacer()
                if let c = model.current, case .reader = model.path.last {
                    Text(c.title).font(Type.caption).foregroundStyle(Ink.soft).lineLimit(1).hidden()
                } else if let c = model.current {
                    Button(c.title) { model.open(c) }.font(Type.caption).buttonStyle(.plain).lineLimit(1)
                }
            }
        }
        .padding(.horizontal, Space.xl)
        .padding(.vertical, Space.m)
        .glassEffect(.regular, in: .rect(cornerRadius: Radius.l))
    }
}
```

Space, left and right arrows: add to `AloudApp`'s scene:

```swift
        .commands {
            CommandMenu("Playback") {
                Button(model.player.isPlaying ? "Pause" : "Play") { model.player.toggle() }
                    .keyboardShortcut(.space, modifiers: [])
                Button("Back 15 seconds") { model.player.skip(seconds: -Player.skipSeconds) }
                    .keyboardShortcut(.leftArrow, modifiers: [])
                Button("Forward 15 seconds") { model.player.skip(seconds: Player.skipSeconds) }
                    .keyboardShortcut(.rightArrow, modifiers: [])
                Button("Faster") { model.player.rate = model.player.rate.next }
                    .keyboardShortcut("]", modifiers: .command)
            }
        }
```

Menu shortcuts without modifiers fire only when no text field has focus, which is the spec's rule.

- [ ] **Step 2: Run and look**

Run: `make dev`.
Expected: the bar sits at the bottom of both surfaces once something is loaded, in glass, play/pause toggles, 15 s lands on sentence starts, the rate cycles and the menu picks, the scrubber seeks, and Space works everywhere except in the editor. Back to the library while playing: audio continues, the title in the bar returns to the reader.

- [ ] **Step 3: Check, commit**

Run: `make check && make test`.

```bash
git add -A && git commit -m "app: transport bar and playback keys"
```

---

### Task 19: Close out milestone 5

**Files:**
- Modify: `README.md` (create), `docs/superpowers/specs/2026-09-09-aloud-design.md` (the two notes below)

- [ ] **Step 1: README**

```markdown
# Aloud

Reads your text files to you.
macOS 26, Swift.

    brew install watchexec xcodegen
    make watch      # rebuild and relaunch on save
    make gallery    # the component page
    make test
    make check

`Aloud --say path/to/file.md` speaks a file from the terminal.
`Aloud --silent` runs with a fake voice for UI work.
```

- [ ] **Step 2: Spec notes**

In the Reader section of the spec, after the Edit sentence, add:

```
Editing a Markdown file edits its raw source, not the extracted prose; v1's first plan restricts Edit to plain text until the raw-source editor lands.
```

In the Library section, after the status-line sentence, add:

```
The pre-start estimate reads the file's byte count at one word per six bytes, since only the first 600 bytes are read at scan time.
```

- [ ] **Step 3: Full pass**

Run: `make check && make test && make dev`, then walk the spec's Library, Reader and Transport bar sections against the running app and fix any mismatch before committing.

- [ ] **Step 4: Commit**

```bash
git add -A && git commit -m "docs: readme and the two v1 notes"
```

---

## Self-review

**Spec coverage for milestones 1 to 5:** Makefile and dev loop (T1), tokens and lint (T2), components and gallery (T3), Script/splitter/estimate (T4), extractor protocol and plain text (T5), Markdown rules including front matter, tables, code blocks, links, images (T6), extraction cache off the main actor (T7), document types, titles, scanner with ignore rules (T8), note naming and saves (T9), recursive watcher (T10), progress store debounced 1 s (T11), voices, eight rate steps, timeline (T12), per-sentence player, seek, skip on boundary, finished (T13), Apple provider and `--say` (T14), bookmarks, model, route, restore-last (T15), library grid with statuses (T16), reader highlight, click-to-seek, follow, A/A, edit for plain text, mark finished (T17), transport bar, keys, title-in-bar (T18).

**Deferred to plan 2 by design:** PDF, paste-to-note and drop, search, right-click menu, voice popover, menu-bar player, hotkey, Settings, Now Playing, output-device pause, raw Markdown editing, Notice for missing voices.

**Type consistency:** `Player.skip(seconds:)` takes `Double`; `Player.skipSeconds` is `Double`; `Rate.factor` feeds `Estimate.duration(words:factor:)`; `Document` gains `bytes` in T15 and every initializer call in T8, T9, T15 must carry it; `SourceKind` (Prose) and `DocumentType` (Vault) are mapped in `AppModel` only.
