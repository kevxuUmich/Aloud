# Aloud Complete Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Finish v1 of Aloud on top of plan 1: PDF, paste and drop and import, search and list view and the right-click menu, the voice popover, the menu-bar player, the global hotkey, Settings, Now Playing and media keys, the output-device pause, raw Markdown editing, live reload of a changed file, and the small things plan 1 deferred.

**Architecture:** Same package as plan 1: `Prose`, `Vault`, `Speech`, `AloudUI` libraries hold every rule and are tested with `swift test`; the `Aloud` executable composes them. New rules go into the libraries first (PDF cleanup, import naming, search, voice grouping, Now Playing bridge, device watcher, script re-anchoring), and each app surface is a thin view over them. The app moves from `WindowGroup` to a single `Window` plus a `MenuBarExtra` and a `Settings` scene.

**Tech Stack:** Swift 6.2 strict concurrency, SwiftUI on macOS 26 (Liquid Glass), Swift Testing, PDFKit, MediaPlayer, CoreAudio, ServiceManagement, `sindresorhus/KeyboardShortcuts`, swift-markdown.

**Spec:** `docs/superpowers/specs/2026-09-09-aloud-design.md`

Plan 1 was `docs/superpowers/plans/2026-09-09-aloud-core.md` and shipped as PR #1 on branch `core`; this plan branches from that.

## Global Constraints

- macOS 26 only; Swift 6 language mode with strict concurrency in every target.
- No number, colour, font size or duration literal in `Sources/Aloud` or `Sources/AloudUI` outside `Sources/AloudUI/Tokens.swift` (`Tests/AloudUITests/LiteralLintTests.swift` enforces the common forms; also avoid bare numeric `let`s and `* 2` arithmetic in views).
- Sentence splitting is `Prose.SentenceSplitter` everywhere; PDF prose goes through the same splitter.
- Duration estimate is 160 words per minute at rate 1.0; rate steps are exactly 0.75, 1, 1.25, 1.5, 1.75, 2, 2.5, 3.
- Speech is one utterance per sentence; one `Player` shared by the window and the menu-bar item.
- Progress lives in Application Support as JSON keyed by file path, never in the user's files.
- Accessibility: icon-only buttons carry `accessibilityLabel`; actions are `Button`s, navigation is links; decorative images are `accessibilityHidden(true)`; async notices are announced.
- Every commit passes `make check` and `make test`. No em dash in any file (plain dash). One sentence per line in Markdown. No co-author line in commits.
- Tests run through `make test` on this machine (the Makefile carries the flags `swift test` needs with the command-line tools alone).

---

## File structure

```
Package.swift                                    + KeyboardShortcuts dependency
Sources/
  Prose/
    PDFExtractor.swift                           PDFKit text, cleanup rules
    ScriptAnchor.swift                           re-find a sentence in a re-extracted script
  Vault/
    Importer.swift                               copy files into a folder, collision names
    Search.swift                                 title and body search
    Trash.swift                                  move a document to the Trash
    RootStore.swift                              (modify) last-known path per bookmark, unresolved list
    Defaults.swift                               typed UserDefaults keys shared by app and Settings
  Speech/
    VoiceGroups.swift                            voices grouped by language, current first
    NowPlaying.swift                             MPNowPlayingInfoCenter + MPRemoteCommandCenter bridge
    OutputDeviceWatcher.swift                    CoreAudio default-output listener
    Player.swift                                 (modify) voice fallback notice hook
  AloudUI/
    Components/VoiceRow.swift
    Components/GlassBar.swift                    (modify) takes any content, used by the transport bar
    Components/FolderCard.swift                  (modify) label matches caption
    Components/Card.swift                        (modify) label without trailing comma
    Components/ListRow.swift                     list-view row
    Tokens.swift                                 (modify) new tokens named per task
  Aloud/
    AloudApp.swift                               (modify) Window + MenuBarExtra + Settings scenes, hotkey
    AppModel.swift                               (modify) paste, import, drop, search, voice, reload
    LibraryView.swift                            (modify) + menu, search, list toggle, context menu, drop, paste
    ReaderView.swift                             (modify) raw Markdown editing, blur and Cmd+S save, dirty guard
    ReaderTextView.swift                         (modify) keyboard scroll cancels follow
    TransportBarView.swift                       (modify) voice button, GlassBar, notice line
    VoicePopover.swift
    MenuBarPanel.swift
    SettingsView.swift
Tests/
  ProseTests/PDFExtractorTests.swift, ScriptAnchorTests.swift, Fixtures/TestPDF.swift
  VaultTests/ImporterTests.swift, SearchTests.swift, TrashTests.swift, RootStoreTests.swift (modify)
  SpeechTests/VoiceGroupsTests.swift, NowPlayingTests.swift, OutputDeviceWatcherTests.swift, PlayerTests.swift (modify)
  AloudUITests/GalleryTests.swift (modify)
```

---

### Task 1: PDF extractor

**Files:**
- Create: `Sources/Prose/PDFExtractor.swift`, `Tests/ProseTests/PDFExtractorTests.swift`, `Tests/ProseTests/Fixtures/TestPDF.swift`
- Modify: `Sources/Prose/Extractor.swift` (`.pdf` case), `Sources/Aloud/AppModel.swift` (kind mapping), `Sources/Aloud/AloudApp.swift` (`say` kind mapping)

**Interfaces:**
- Consumes: `Extractor`, `ExtractOptions`, `Paragraphs.normalize`, `SentenceSplitter.split`, `Script`.
- Produces: `public struct PDFExtractor: Extractor`; `enum PDFCleanup` with `static func clean(pages: [String]) -> String` (pure, tested); `SourceKind(documentType:)` helper in `AppModel` becomes `Document.sourceKind` in `Vault`? No: `Vault` must not import `Prose` types into its public API beyond what it already does. Add `extension SourceKind { public init(_ type: DocumentType) }` in `Sources/Speech/DocumentStatus.swift`'s neighbour file `Sources/Speech/SourceKind+DocumentType.swift` (Speech already imports both).

- [ ] **Step 1: Test PDF builder**

`Tests/ProseTests/Fixtures/TestPDF.swift`:

```swift
import CoreGraphics
import CoreText
import Foundation

/// Builds a real PDF from lines of text, one array per page, top to bottom,
/// so PDFKit's `string` comes back in reading order.
enum TestPDF {
    static func make(pages: [[String]]) -> Data {
        let data = NSMutableData()
        var box = CGRect(x: 0, y: 0, width: 400, height: 600)
        let consumer = CGDataConsumer(data: data as CFMutableData)!
        let ctx = CGContext(consumer: consumer, mediaBox: &box, nil)!
        let font = CTFontCreateWithName("Helvetica" as CFString, 12, nil)
        for lines in pages {
            ctx.beginPDFPage(nil)
            var y: CGFloat = 560
            for line in lines {
                let attr = NSAttributedString(string: line, attributes: [.font: font])
                let ctLine = CTLineCreateWithAttributedString(attr)
                ctx.textPosition = CGPoint(x: 40, y: y)
                CTLineDraw(ctLine, ctx)
                y -= 18
            }
            ctx.endPDFPage()
        }
        ctx.closePDF()
        return data as Data
    }
}
```

- [ ] **Step 2: Failing tests**

```swift
import Foundation
import Testing
@testable import Prose

@Suite struct PDFExtractorTests {
    @Test func readsPagesInOrder() throws {
        let pdf = TestPDF.make(pages: [["first sentence.", "second sentence."], ["third sentence."]])
        let s = try PDFExtractor().script(from: pdf, options: .default)
        #expect(s.sentences.map(\.text) == ["first sentence.", "second sentence.", "third sentence."])
    }
    @Test func joinsHyphenatedLineBreaks() {
        let out = PDFCleanup.clean(pages: ["the exper-\niment worked."])
        #expect(out == "the experiment worked.")
    }
    @Test func dropsLinesRepeatedOnMostPages() {
        let out = PDFCleanup.clean(pages: [
            "Journal of Things\nbody one.", "Journal of Things\nbody two.", "Journal of Things\nbody three.",
        ])
        #expect(!out.contains("Journal of Things"))
        #expect(out.contains("body one."))
    }
    @Test func keepsALineRepeatedOnHalfOrFewerPages() {
        let out = PDFCleanup.clean(pages: ["Intro\nbody.", "Intro\nbody.", "other\nbody.", "other\nbody."])
        #expect(out.contains("Intro"))
    }
    @Test func dropsBarePageNumbers() {
        let out = PDFCleanup.clean(pages: ["body.\n12", "more.\n13"])
        #expect(!out.contains("12")); #expect(!out.contains("13"))
    }
    @Test func collapsesSingleLineBreaksInsideAParagraph() {
        let out = PDFCleanup.clean(pages: ["one line\nsame paragraph.\n\nnext paragraph."])
        #expect(out == "one line same paragraph.\n\nnext paragraph.")
    }
    @Test func imageOnlyPDFIsEmpty() throws {
        let pdf = TestPDF.make(pages: [[]])
        let s = try PDFExtractor().script(from: pdf, options: .default)
        #expect(s.sentences.isEmpty)
    }
    @Test func garbageIsUndecodable() {
        #expect(throws: ExtractError.self) { try PDFExtractor().script(from: Data([1, 2, 3]), options: .default) }
    }
    @Test func registryKnowsPDF() throws { _ = try Extractors.extractor(for: .pdf) }
}
```

Run: `make test` → FAIL (`PDFExtractor` undefined).

- [ ] **Step 3: Implement**

`Sources/Prose/PDFExtractor.swift`:

```swift
import Foundation
import PDFKit

public struct PDFExtractor: Extractor {
    public init() {}
    public func script(from data: Data, options: ExtractOptions) throws -> Script {
        guard let doc = PDFDocument(data: data) else { throw ExtractError.undecodable }
        var pages: [String] = []
        for i in 0..<doc.pageCount { pages.append(doc.page(at: i)?.string ?? "") }
        let source = Paragraphs.normalize(PDFCleanup.clean(pages: pages))
        return Script(source: source, sentences: SentenceSplitter.split(source))
    }
}

/// The layout noise PDFKit hands back with the text: running headers and footers,
/// page numbers, hyphenation at line ends, and one line break per printed line.
enum PDFCleanup {
    static func clean(pages: [String]) -> String {
        let pageLines = pages.map { $0.components(separatedBy: .newlines).map { $0.trimmingCharacters(in: .whitespaces) } }
        let repeated = repeatedLines(pageLines)
        var out: [String] = []
        for lines in pageLines {
            var kept: [String] = []
            for line in lines {
                if repeated.contains(line) { continue }
                if isBarePageNumber(line) { continue }
                kept.append(line)
            }
            out.append(joinHyphens(kept).joined(separator: "\n"))
        }
        return out.filter { !$0.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }.joined(separator: "\n\n")
    }

    /// A non-empty line that appears on more than half the pages is a running header or footer.
    static func repeatedLines(_ pages: [[String]]) -> Set<String> {
        guard pages.count > 1 else { return [] }
        var counts: [String: Int] = [:]
        for lines in pages { for line in Set(lines) where !line.isEmpty { counts[line, default: 0] += 1 } }
        return Set(counts.filter { $0.value * 2 > pages.count }.keys)
    }

    static func isBarePageNumber(_ line: String) -> Bool {
        !line.isEmpty && line.allSatisfy(\.isNumber) && line.count <= 4
    }

    /// "exper-" + "iment" -> "experiment"; the split word is rejoined on the first line.
    static func joinHyphens(_ lines: [String]) -> [String] {
        var out: [String] = []
        var carry = ""
        for line in lines {
            let joined = carry + line
            carry = ""
            if joined.hasSuffix("-"), let last = joined.last, last == "-", joined.count > 1,
               joined[joined.index(before: joined.index(before: joined.endIndex))].isLetter {
                carry = String(joined.dropLast())
            } else {
                out.append(joined)
            }
        }
        if !carry.isEmpty { out.append(carry) }
        return out
    }
}
```

Note `collapsesSingleLineBreaksInsideAParagraph` passes because `Paragraphs.normalize` runs after `clean`; the unit test on `clean` alone expects the single break kept, so make that test call `Paragraphs.normalize(PDFCleanup.clean(...))` instead. Update the test accordingly.

In `Extractor.swift` the `.pdf` case returns `PDFExtractor()`; delete the `.unsupported` throw and update `PlainTextExtractorTests.registryKnowsKinds` to expect no throw for `.pdf`.

`Sources/Speech/SourceKind+DocumentType.swift`:

```swift
import Prose
import Vault

extension SourceKind {
    public init(_ type: DocumentType) {
        switch type {
        case .markdown: self = .markdown
        case .plainText: self = .plainText
        case .pdf: self = .pdf
        }
    }
}
```

Replace both `doc.type == .markdown ? .markdown : .plainText` sites in `AppModel.swift` and `AloudApp.say` with `SourceKind(doc.type)` / `SourceKind(type)`. `restoreLast` no longer skips PDFs.

- [ ] **Step 4: Run, check, commit**

Run: `make check && make test` → all PASS.

```bash
git add -A && git commit -m "prose: pdf through pdfkit with the cleanup pass"
```

---

### Task 2: Import, paste and drop

**Files:**
- Create: `Sources/Vault/Importer.swift`, `Sources/Vault/Defaults.swift`, `Tests/VaultTests/ImporterTests.swift`
- Modify: `Sources/Aloud/AppModel.swift`, `Sources/Aloud/LibraryView.swift`, `Sources/Aloud/AloudApp.swift`

**Interfaces:**
- Produces:
  - `public enum Importer { public static func importFiles(_ urls: [URL], into folder: URL) throws -> [URL] }` copies supported files (by `DocumentType(url:)`), skips others, resolves name collisions with ` 2`, ` 3`.
  - `public enum Defaults { public static let suite = UserDefaults.standard; public static var noteFolderPath: String?; public static var voiceID: String?; public static var rateFactor: Double?; public static var skipCode: Bool; public static var showMenuBar: Bool; public static var listView: Bool }` as computed properties over `UserDefaults` with fixed keys.
  - `AppModel.noteFolder: URL?` (the default folder for new notes: `Defaults.noteFolderPath` if it is under a root, else the first root), `func pasteNote()`, `func importFiles(_ urls: [URL])`, `func drop(_ urls: [URL])`.

- [ ] **Step 1: Failing tests**

```swift
import Foundation
import Testing
@testable import Vault

@Suite struct ImporterTests {
    func temp() throws -> URL {
        let u = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: u, withIntermediateDirectories: true)
        return u
    }
    @Test func copiesSupportedFilesAndSkipsOthers() throws {
        let src = try temp(), dst = try temp()
        try "a".write(to: src.appendingPathComponent("a.md"), atomically: true, encoding: .utf8)
        try "b".write(to: src.appendingPathComponent("b.png"), atomically: true, encoding: .utf8)
        let out = try Importer.importFiles([src.appendingPathComponent("a.md"), src.appendingPathComponent("b.png")], into: dst)
        #expect(out.map(\.lastPathComponent) == ["a.md"])
        #expect(try String(contentsOf: dst.appendingPathComponent("a.md"), encoding: .utf8) == "a")
    }
    @Test func collisionsCount() throws {
        let src = try temp(), dst = try temp()
        try "x".write(to: src.appendingPathComponent("n.txt"), atomically: true, encoding: .utf8)
        try "old".write(to: dst.appendingPathComponent("n.txt"), atomically: true, encoding: .utf8)
        let out = try Importer.importFiles([src.appendingPathComponent("n.txt")], into: dst)
        #expect(out.map(\.lastPathComponent) == ["n 2.txt"])
        #expect(try String(contentsOf: dst.appendingPathComponent("n.txt"), encoding: .utf8) == "old")
    }
}
```

- [ ] **Step 2: Implement**

`Importer.swift`:

```swift
import Foundation

public enum Importer {
    /// Copies the supported files into `folder`, never overwriting; returns the new URLs.
    public static func importFiles(_ urls: [URL], into folder: URL) throws -> [URL] {
        let fm = FileManager.default
        var out: [URL] = []
        for url in urls where DocumentType(url: url) != nil {
            let base = url.deletingPathExtension().lastPathComponent
            let ext = url.pathExtension
            var candidate = folder.appendingPathComponent("\(base).\(ext)")
            var n = 2
            while fm.fileExists(atPath: candidate.path) {
                candidate = folder.appendingPathComponent("\(base) \(n).\(ext)")
                n += 1
            }
            try fm.copyItem(at: url, to: candidate)
            out.append(candidate)
        }
        return out
    }
}
```

`Defaults.swift`:

```swift
import Foundation

/// The app's settings, one typed accessor per key, so the app and Settings agree on names.
public enum Defaults {
    nonisolated(unsafe) public static var store = UserDefaults.standard
    public static var noteFolderPath: String? {
        get { store.string(forKey: "noteFolderPath") }
        set { store.set(newValue, forKey: "noteFolderPath") }
    }
    public static var voiceID: String? {
        get { store.string(forKey: "voiceID") }
        set { store.set(newValue, forKey: "voiceID") }
    }
    public static var rateFactor: Double? {
        get { store.object(forKey: "rateFactor") as? Double }
        set { store.set(newValue, forKey: "rateFactor") }
    }
    public static var skipCode: Bool {
        get { store.object(forKey: "skipCode") as? Bool ?? true }
        set { store.set(newValue, forKey: "skipCode") }
    }
    public static var showMenuBar: Bool {
        get { store.object(forKey: "showMenuBar") as? Bool ?? true }
        set { store.set(newValue, forKey: "showMenuBar") }
    }
    public static var listView: Bool {
        get { store.bool(forKey: "listView") }
        set { store.set(newValue, forKey: "listView") }
    }
}
```

`nonisolated(unsafe)` is the one place it is used, so tests can swap in a suite; say so in a comment.

`AppModel` additions:

```swift
    var noteFolder: URL? {
        if let p = Defaults.noteFolderPath, roots.contains(where: { p.hasPrefix($0.path) }) {
            return URL(fileURLWithPath: p)
        }
        return roots.first
    }

    var extractOptions: ExtractOptions { ExtractOptions(skipCode: Defaults.skipCode) }

    /// Clipboard text becomes a note in the default folder and opens ready to play.
    func pasteNote(andPlay: Bool = false) {
        guard let text = NSPasteboard.general.string(forType: .string)?.trimmingCharacters(in: .whitespacesAndNewlines),
              !text.isEmpty else { notice = "The clipboard has no text"; return }
        guard let folder = noteFolder else { notice = "Pick a folder to read from first"; return }
        Task {
            do {
                let url = try await vault.makeNote(text: text, in: folder)
                await refresh()
                if let doc = document(at: url) { open(doc); if andPlay { player.play() } }
            } catch { notice = "Could not save the note: \(error.localizedDescription)" }
        }
    }

    func importFiles(_ urls: [URL], into folder: URL? = nil) {
        guard let target = folder ?? currentFolderURL ?? noteFolder else { notice = "Pick a folder to read from first"; return }
        Task {
            do {
                let added = try Importer.importFiles(urls, into: target)
                await refresh()
                if added.isEmpty { notice = "Nothing to import: Aloud reads .md, .txt and .pdf" }
                else if added.count == 1, let doc = document(at: added[0]) { open(doc) }
            } catch { notice = "Could not import: \(error.localizedDescription)" }
        }
    }

    /// Dropped folders become roots; dropped files are imported into the current folder.
    func drop(_ urls: [URL]) {
        var isDir: ObjCBool = false
        let folders = urls.filter { FileManager.default.fileExists(atPath: $0.path, isDirectory: &isDir) && isDir.boolValue }
        let files = urls.filter { !folders.contains($0) }
        folders.forEach(addRoot)
        if !files.isEmpty { importFiles(files) }
    }

    func pickFilesToImport() {
        let panel = NSOpenPanel()
        panel.canChooseFiles = true; panel.canChooseDirectories = false; panel.allowsMultipleSelection = true
        panel.allowedContentTypes = [.plainText, .pdf, UTType(filenameExtension: "md") ?? .plainText]
        panel.prompt = "Import"
        if panel.runModal() == .OK { importFiles(panel.urls) }
    }

    var currentFolderURL: URL? {
        if case .folder(let url)? = path.last { return url }
        return nil
    }

    func document(at url: URL) -> Document? {
        func find(_ folders: [Folder]) -> Document? {
            for f in folders {
                if let d = f.documents.first(where: { $0.url.path == url.path }) { return d }
                if let d = find(f.folders) { return d }
            }
            return nil
        }
        return find(tree)
    }
```

`import UniformTypeIdentifiers` at the top of `AppModel.swift`. `open(_:)` passes `extractOptions` instead of `.default`.

`LibraryView`: replace the toolbar's single item with a `+` `Menu` and keep Add vault folder inside it:

```swift
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                Menu {
                    Button("New Note from Clipboard") { model.pasteNote() }
                    Button("Import Files...") { model.pickFilesToImport() }
                    Divider()
                    Button("Add Vault Folder...") { model.pickRootFolder() }
                } label: {
                    Image(systemName: "plus")
                }
                .accessibilityLabel("Add")
                .help("Add")
            }
        }
        .dropDestination(for: URL.self) { urls, _ in
            model.drop(urls)
            return true
        }
```

`EmptyState(onPickFolder: model.pickRootFolder, onPaste: { model.pasteNote() })`; delete the plan-1 comment.

Cmd+V with no text field focused: in `AloudApp` add to `.commands`:

```swift
            CommandGroup(after: .pasteboard) {
                Button("New Note from Clipboard") { model.pasteNote() }
                    .keyboardShortcut("v", modifiers: [.command, .shift])
            }
```

and on the library's `ScrollView` add `.focusable().focusEffectDisabled().onPasteCommand(of: [.plainText]) { _ in model.pasteNote() }`. The spec's bare Cmd+V works when the library has focus; Cmd+Shift+V works everywhere. Note in the spec (Task 11) that Cmd+Shift+V is the always-available form.

- [ ] **Step 3: Run, look, commit**

Run: `make check && make test && make dev`: `+` menu present; New Note from Clipboard creates a file titled from the first line and opens it; drop a `.md` onto the window and it appears.

```bash
git add -A && git commit -m "app: notes from the clipboard, import, drop, the plus menu"
```

---

### Task 3: Search, list view, right-click

**Files:**
- Create: `Sources/Vault/Search.swift`, `Sources/Vault/Trash.swift`, `Sources/AloudUI/Components/ListRow.swift`, `Tests/VaultTests/SearchTests.swift`, `Tests/VaultTests/TrashTests.swift`
- Modify: `Sources/Aloud/LibraryView.swift`, `Sources/Aloud/AppModel.swift`, `Sources/AloudUI/Gallery.swift`, `Tests/AloudUITests/GalleryTests.swift`

**Interfaces:**
- Produces:
  - `public enum Search { public static func matches(_ query: String, in documents: [Document]) async -> Set<String> }` returning matching document ids: title match (case- and diacritic-insensitive) or body match for `.markdown`/`.plainText` by reading the file; PDFs match on title only. Empty query returns all ids.
  - `public enum Trash { public static func move(_ document: Document) throws -> URL }` via `FileManager.trashItem`.
  - `public struct ListRow: View { init(title:, status:, symbol:) }`.
  - `AppModel.searchQuery: String`, `searchResults: Set<String>?` (nil when no query), `func trash(_ doc: Document)`, `func reveal(_ doc: Document)`.

- [ ] **Step 1: Failing tests**

`SearchTests.swift`:

```swift
import Foundation
import Testing
@testable import Vault

@Suite struct SearchTests {
    func doc(_ name: String, _ body: String, in dir: URL) throws -> Document {
        let url = dir.appendingPathComponent(name)
        try body.write(to: url, atomically: true, encoding: .utf8)
        return Document(url: url, title: Title.from(text: body, fallback: name), preview: body, modified: .now, bytes: body.utf8.count, type: DocumentType(url: url)!)
    }
    @Test func matchesTitleAndBody() async throws {
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        let a = try doc("a.md", "# Fast Year\n\nnothing here", in: dir)
        let b = try doc("b.txt", "plain start\n\nthe word hamming appears", in: dir)
        let hits = await Search.matches("hamming", in: [a, b])
        #expect(hits == [b.id])
        let byTitle = await Search.matches("fast", in: [a, b])
        #expect(byTitle == [a.id])
        let diacritic = await Search.matches("HAMMÍNG", in: [a, b])
        #expect(diacritic == [b.id])
    }
    @Test func emptyQueryMatchesAll() async throws {
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        let a = try doc("a.md", "x", in: dir)
        #expect(await Search.matches("  ", in: [a]) == [a.id])
    }
}
```

`TrashTests.swift`:

```swift
import Foundation
import Testing
@testable import Vault

@Suite struct TrashTests {
    @Test func movesTheFileOut() throws {
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        let url = dir.appendingPathComponent("gone.md")
        try "bye".write(to: url, atomically: true, encoding: .utf8)
        let doc = Document(url: url, title: "gone", preview: "", modified: .now, bytes: 3, type: .markdown)
        let moved = try Trash.move(doc)
        #expect(!FileManager.default.fileExists(atPath: url.path))
        #expect(FileManager.default.fileExists(atPath: moved.path))
        try? FileManager.default.removeItem(at: moved)
    }
}
```

`trashItem` on a temp-volume file may fail in a sandboxed test runner; if it throws `NSCocoaErrorDomain 3328`, write the file under `FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent("Library/Caches/AloudTests")` instead and note it.

- [ ] **Step 2: Implement**

`Search.swift`:

```swift
import Foundation

public enum Search {
    /// Documents whose title or body contains the query, ignoring case and diacritics.
    /// PDF bodies are not read here; a PDF matches on its title.
    public static func matches(_ query: String, in documents: [Document]) async -> Set<String> {
        let q = query.trimmingCharacters(in: .whitespaces)
        guard !q.isEmpty else { return Set(documents.map(\.id)) }
        return await Task.detached(priority: .userInitiated) {
            var hits = Set<String>()
            for d in documents {
                if d.title.localizedStandardContains(q) { hits.insert(d.id); continue }
                guard d.type != .pdf, let body = try? String(contentsOf: d.url, encoding: .utf8) else { continue }
                if body.localizedStandardContains(q) { hits.insert(d.id) }
            }
            return hits
        }.value
    }
}
```

`Trash.swift`:

```swift
import Foundation

public enum Trash {
    public static func move(_ document: Document) throws -> URL {
        var moved: NSURL?
        try FileManager.default.trashItem(at: document.url, resultingItemURL: &moved)
        return (moved as URL?) ?? document.url
    }
}
```

`ListRow.swift`:

```swift
import SwiftUI

public struct ListRow: View {
    public let title: String
    public let status: String
    public let symbol: String
    public init(title: String, status: String, symbol: String) { self.title = title; self.status = status; self.symbol = symbol }
    public var body: some View {
        HStack(spacing: Space.m) {
            Image(systemName: symbol).foregroundStyle(Ink.soft).accessibilityHidden(true)
            Text(title).font(Type.cardTitle).lineLimit(1)
            Spacer()
            Text(status).font(Type.caption).foregroundStyle(Ink.soft)
        }
        .padding(.vertical, Space.s)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(status.isEmpty ? title : "\(title), \(status)")
    }
}
```

Add `ListRow` to the gallery and its `sections` list (test expects `>= 8`, still true).

`AppModel` additions:

```swift
    var searchQuery = "" { didSet { search() } }
    var searchResults: Set<String>?
    private var searchTask: Task<Void, Never>?

    private func search() {
        searchTask?.cancel()
        let q = searchQuery
        guard !q.trimmingCharacters(in: .whitespaces).isEmpty else { searchResults = nil; return }
        let docs = allDocuments(in: tree)
        searchTask = Task {
            try? await Task.sleep(for: .milliseconds(Int(Motion.searchDebounceMS)))
            guard !Task.isCancelled else { return }
            let hits = await Search.matches(q, in: docs)
            guard !Task.isCancelled else { return }
            searchResults = hits
        }
    }

    func allDocuments(in folders: [Folder]) -> [Document] {
        folders.flatMap { $0.documents + allDocuments(in: $0.folders) }
    }

    func trash(_ doc: Document) {
        do {
            _ = try Trash.move(doc)
            if current?.id == doc.id { player.pause() }
            Task { await refresh() }
        } catch { notice = "Could not move \(doc.title) to the Trash: \(error.localizedDescription)" }
    }

    func reveal(_ doc: Document) { NSWorkspace.shared.activateFileViewerSelecting([doc.url]) }
```

`Motion.searchDebounceMS: Double = 200` goes into Tokens; the model imports `AloudUI` for it (add `import AloudUI` to AppModel.swift; the target already depends on it).

`LibraryView`: when `model.searchResults != nil`, show a flat list of all matching documents across the tree (no folders) titled "Search"; otherwise the existing grid. `.searchable(text: $model.searchQuery, placement: .toolbar, prompt: "Search")` on the view (pass `@Bindable var model`). Grid/list toggle: `@AppStorage("listView") private var listView = false` (same key as `Defaults.listView`), a toolbar `Picker` with `.pickerStyle(.segmented)` of two `Image`s (`square.grid.2x2`, `list.bullet`) each with `.accessibilityLabel`; list mode renders `ListRow(title:status:symbol:)` with `doc.fill` / `folder.fill` in a `LazyVStack`. Context menu on every document card and row:

```swift
.contextMenu {
    Button("Play") { model.open(doc); model.player.play() }
    Button(model.progress.progress(for: doc.url)?.finished == true ? "Mark Unfinished" : "Mark Finished") { model.toggleFinished(doc) }
    Divider()
    Button("Reveal in Finder") { model.reveal(doc) }
    Button("Move to Trash", role: .destructive) { model.trash(doc) }
}
```

The `Delete` key on a focused card also trashes (`.onDeleteCommand` on the card button).

- [ ] **Step 3: Run, look, commit**

Run: `make check && make test && make dev`: type in the search field, results narrow by title and body; toggle list; right-click a card.

```bash
git add -A && git commit -m "app: search, list view, and the right-click menu"
```

---

### Task 4: Voice popover and remembered voice and rate

**Files:**
- Create: `Sources/Speech/VoiceGroups.swift`, `Sources/AloudUI/Components/VoiceRow.swift`, `Sources/Aloud/VoicePopover.swift`, `Tests/SpeechTests/VoiceGroupsTests.swift`
- Modify: `Sources/Speech/Player.swift`, `Sources/Aloud/TransportBarView.swift`, `Sources/Aloud/AppModel.swift`, `Sources/AloudUI/Gallery.swift`, `Tests/SpeechTests/PlayerTests.swift`

**Interfaces:**
- Produces:
  - `public struct VoiceGroup: Identifiable, Hashable, Sendable { public let language: String; public let name: String; public let voices: [Voice]; public var id: String { language } }`
  - `public enum VoiceGroups { public static func group(_ voices: [Voice], currentLanguage: String) -> [VoiceGroup] }`: grouped by the language part of the BCP-47 tag, the current language's group first, then by display name; inside a group sorted by quality descending then name; `name` from `Locale.current.localizedString(forLanguageCode:)`; region string per voice via `Voice.regionName` (`Locale.current.localizedString(forRegionCode:)`).
  - `Player.onVoiceUnavailable: ((Voice) -> Void)?` fired when `speak` is asked for a voice the provider no longer lists; the player falls back to `provider.defaultVoice` for that and later sentences.
  - `VoiceProvider` gains `func preview(_ voice: Voice)` speaking one fixed sentence (`VoiceProvider.previewText = "Nobody really teaches you research."`); the fake records it.
  - `VoiceRow(name:, region:, quality:, isSelected:, onPreview:, onPick:)`.
  - `AppModel.pickVoice(_:)` persists `Defaults.voiceID`; `Player.rate` changes persist `Defaults.rateFactor`; both restored on launch.

- [ ] **Step 1: Failing tests**

```swift
import Testing
@testable import Speech

@Suite struct VoiceGroupsTests {
    let voices = [
        Voice(id: "1", name: "Samantha", language: "en-US", quality: .enhanced),
        Voice(id: "2", name: "Daniel", language: "en-GB", quality: .premium),
        Voice(id: "3", name: "Majed", language: "ar-001", quality: .standard),
        Voice(id: "4", name: "Aaron", language: "en-US", quality: .standard),
    ]
    @Test func currentLanguageComesFirstAndQualityLeads() {
        let g = VoiceGroups.group(voices, currentLanguage: "en-US")
        #expect(g.first?.language == "en")
        #expect(g.first?.voices.map(\.name) == ["Daniel", "Samantha", "Aaron"])
        #expect(g.map(\.language) == ["en", "ar"])
    }
    @Test func regionNameIsHuman() {
        #expect(Voice(id: "x", name: "x", language: "en-GB", quality: .standard).regionName == "United Kingdom")
    }
}
```

`PlayerTests` addition:

```swift
    @Test func missingVoiceFallsBackAndReports() {
        let (p, fake) = make()
        var reported: Voice?
        p.onVoiceUnavailable = { reported = $0 }
        p.voice = Voice(id: "ghost", name: "Ghost", language: "en-US", quality: .standard)
        p.play()
        #expect(reported?.id == "ghost")
        #expect(fake.spoken.last?.voice?.id == "fake")
        #expect(p.voice?.id == "fake")
    }
```

- [ ] **Step 2: Implement**

`VoiceGroups.swift`:

```swift
import Foundation

public struct VoiceGroup: Identifiable, Hashable, Sendable {
    public let language: String
    public let name: String
    public let voices: [Voice]
    public var id: String { language }
}

public enum VoiceGroups {
    public static func group(_ voices: [Voice], currentLanguage: String) -> [VoiceGroup] {
        let current = code(currentLanguage)
        var buckets: [String: [Voice]] = [:]
        for v in voices { buckets[code(v.language), default: []].append(v) }
        let groups = buckets.map { key, vs in
            VoiceGroup(
                language: key,
                name: Locale.current.localizedString(forLanguageCode: key) ?? key,
                voices: vs.sorted { ($0.quality, $1.name) > ($1.quality, $0.name) })
        }
        return groups.sorted {
            if $0.language == current { return true }
            if $1.language == current { return false }
            return $0.name.localizedStandardCompare($1.name) == .orderedAscending
        }
    }
    static func code(_ tag: String) -> String { String(tag.split(separator: "-").first ?? Substring(tag)) }
}

extension Voice {
    public var regionName: String? {
        let parts = language.split(separator: "-")
        guard parts.count > 1 else { return nil }
        return Locale.current.localizedString(forRegionCode: String(parts[1]))
    }
}
```

The quality sort compares tuples; write it as `if $0.quality != $1.quality { return $0.quality > $1.quality }; return $0.name < $1.name` for clarity.

`VoiceProvider` gains:

```swift
    static var previewText: String { "Nobody really teaches you research." }
    @MainActor func preview(_ voice: Voice)
```

`FakeVoiceProvider.preview` appends to `previewed: [Voice]`; `AppleVoiceProvider.preview` stops and speaks the text with that voice at `Rate.x1.appleRate` without touching `onWord`/`onFinish`.

`Player`:

```swift
    public var onVoiceUnavailable: ((Voice) -> Void)?

    private func speakCurrent() {
        ...
        if let v = voice, !provider.voices.contains(where: { $0.id == v.id }) {
            onVoiceUnavailable?(v)
            voice = provider.defaultVoice
        }
        provider.speak(sentence.text, voice: voice, rate: rate, ...)
```

`Player.init(provider:)` keeps `voice = provider.defaultVoice`; `AppModel.init` then applies `Defaults.voiceID` (`provider.voices.first { $0.id == id }`) and `Defaults.rateFactor` (`Rate(rawValue:)`), and sets `player.onVoiceUnavailable = { [weak self] v in self?.notice = "\(v.name) is not available, using the system voice" }`. `AppModel.pickVoice(_ v: Voice)` sets `player.voice = v` and `Defaults.voiceID = v.id`. Rate persistence: `AppModel.setRate(_ r: Rate)` sets both; the transport bar and the Playback menu call it instead of writing `player.rate`.

`VoiceRow.swift`:

```swift
import SwiftUI

public struct VoiceRow: View {
    let name: String
    let region: String?
    let quality: String
    let isSelected: Bool
    let onPreview: () -> Void
    let onPick: () -> Void
    public init(name: String, region: String?, quality: String, isSelected: Bool, onPreview: @escaping () -> Void, onPick: @escaping () -> Void) {
        self.name = name; self.region = region; self.quality = quality; self.isSelected = isSelected; self.onPreview = onPreview; self.onPick = onPick
    }
    public var body: some View {
        HStack(spacing: Space.m) {
            Button(action: onPreview) { Image(systemName: "play.circle") }
                .buttonStyle(.borderless).accessibilityLabel("Preview \(name)")
            Button(action: onPick) {
                VStack(alignment: .leading, spacing: Space.xs) {
                    Text(name).font(Type.cardTitle)
                    HStack(spacing: Space.s) {
                        if let region { Text(region).font(Type.caption).foregroundStyle(Ink.soft) }
                        Text(quality).font(Type.caption).foregroundStyle(Ink.soft)
                    }
                }
                Spacer()
                if isSelected { Image(systemName: "checkmark").accessibilityHidden(true) }
            }
            .buttonStyle(.plain)
            .accessibilityLabel("\(name), \(region ?? ""), \(quality)\(isSelected ? ", selected" : "")")
        }
        .padding(.vertical, Space.s)
    }
}
```

`Sources/Aloud/VoicePopover.swift`:

```swift
import AloudUI
import AppKit
import Speech
import SwiftUI

struct VoicePopover: View {
    var model: AppModel
    var groups: [VoiceGroup] {
        VoiceGroups.group(model.provider.voices, currentLanguage: Locale.current.identifier)
    }
    var body: some View {
        VStack(alignment: .leading, spacing: Space.m) {
            Text("Voice").font(Type.title)
            ScrollView {
                LazyVStack(alignment: .leading, spacing: Space.xs) {
                    ForEach(groups) { g in
                        Text(g.name).font(Type.caption).foregroundStyle(Ink.soft).padding(.top, Space.m)
                        ForEach(g.voices) { v in
                            VoiceRow(
                                name: v.name, region: v.regionName, quality: v.quality.label,
                                isSelected: v.id == model.player.voice?.id,
                                onPreview: { model.provider.preview(v) },
                                onPick: { model.pickVoice(v) })
                        }
                    }
                }
            }
            Button("Get more voices...") {
                NSWorkspace.shared.open(URL(string: "x-apple.systempreferences:com.apple.preference.universalaccess?SpokenContent")!)
            }
            .buttonStyle(.link)
        }
        .padding(Space.xl)
        .frame(width: Size.popoverWidth, height: Size.popoverHeight)
    }
}
```

`Size.popoverWidth: CGFloat = 320`, `Size.popoverHeight: CGFloat = 440` in Tokens. `AppModel` exposes `let provider: any VoiceProvider`.

`TransportBarView`: on the right, before the title, an `IconButton("person.wave.2", label: "Voice")` toggling `@State private var showVoices` with `.popover(isPresented: $showVoices, arrowEdge: .top) { VoicePopover(model: model) }`. The current voice's name is the button's `help`.

- [ ] **Step 3: Run, look, commit**

Run: `make check && make test && make dev`: open the popover, preview a voice, pick one; it takes at the next sentence and survives relaunch.

```bash
git add -A && git commit -m "speech: voice groups, preview, fallback; app: the voice popover"
```

---

### Task 5: Now Playing, media keys, output-device pause

**Files:**
- Create: `Sources/Speech/NowPlaying.swift`, `Sources/Speech/OutputDeviceWatcher.swift`, `Tests/SpeechTests/NowPlayingTests.swift`, `Tests/SpeechTests/OutputDeviceWatcherTests.swift`
- Modify: `Sources/Aloud/AppModel.swift`

**Interfaces:**
- Produces:
  - `@MainActor public final class NowPlaying { public init(player: Player, center: any NowPlayingCenter = SystemNowPlayingCenter(), commands: any RemoteCommands = SystemRemoteCommands()); public func update(title: String?) }`. `NowPlayingCenter` protocol: `func set(info: [String: Any])`, `func set(playing: Bool)`; `RemoteCommands` protocol: `func bind(play: @escaping () -> Void, pause: @escaping () -> Void, toggle: @escaping () -> Void, skipForward: @escaping () -> Void, skipBackward: @escaping () -> Void)`. System implementers wrap `MPNowPlayingInfoCenter.default()` and `MPRemoteCommandCenter.shared()`; fakes in the test.
  - `public final class OutputDeviceWatcher: @unchecked Sendable { public init(onChange: @escaping @Sendable () -> Void); public func stop() }` listening to `kAudioHardwarePropertyDefaultOutputDevice` on the system object.

- [ ] **Step 1: Failing tests**

```swift
import Foundation
import Prose
import Testing
@testable import Speech

@Suite @MainActor struct NowPlayingTests {
    final class FakeCenter: NowPlayingCenter {
        var info: [String: Any] = [:]; var playing: Bool?
        func set(info: [String: Any]) { self.info = info }
        func set(playing: Bool) { self.playing = playing }
    }
    final class FakeCommands: RemoteCommands {
        var play: (() -> Void)?; var pause: (() -> Void)?; var toggle: (() -> Void)?
        var forward: (() -> Void)?; var backward: (() -> Void)?
        func bind(play: @escaping () -> Void, pause: @escaping () -> Void, toggle: @escaping () -> Void,
                  skipForward: @escaping () -> Void, skipBackward: @escaping () -> Void) {
            self.play = play; self.pause = pause; self.toggle = toggle; self.forward = skipForward; self.backward = skipBackward
        }
    }
    @Test func mirrorsTitleAndStateAndAnswersCommands() {
        let fake = FakeVoiceProvider()
        let p = Player(provider: fake)
        let src = "One two three. Four five six."
        p.load(Script(source: src, sentences: SentenceSplitter.split(src)), at: 0)
        let center = FakeCenter(), commands = FakeCommands()
        let np = NowPlaying(player: p, center: center, commands: commands)
        np.update(title: "Essay")
        #expect(center.info["title"] as? String == "Essay")
        commands.play?()
        #expect(p.isPlaying)
        #expect(center.playing == true)
        commands.pause?()
        #expect(!p.isPlaying)
        #expect(center.playing == false)
        commands.forward?()
        #expect(p.sentenceIndex == 1)
    }
}
```

`OutputDeviceWatcherTests`: construct, sleep 100 ms, `stop()` twice; expect no crash (the device cannot be changed from a test).

- [ ] **Step 2: Implement**

`NowPlaying.swift`:

```swift
import Foundation
import MediaPlayer

public protocol NowPlayingCenter: AnyObject {
    func set(info: [String: Any])
    func set(playing: Bool)
}
public protocol RemoteCommands: AnyObject {
    func bind(play: @escaping () -> Void, pause: @escaping () -> Void, toggle: @escaping () -> Void,
              skipForward: @escaping () -> Void, skipBackward: @escaping () -> Void)
}

public final class SystemNowPlayingCenter: NowPlayingCenter {
    public init() {}
    public func set(info: [String: Any]) {
        var mp: [String: Any] = [:]
        if let t = info["title"] { mp[MPMediaItemPropertyTitle] = t }
        if let d = info["duration"] { mp[MPMediaItemPropertyPlaybackDuration] = d }
        if let e = info["elapsed"] { mp[MPNowPlayingInfoPropertyElapsedPlaybackTime] = e }
        if let r = info["rate"] { mp[MPNowPlayingInfoPropertyPlaybackRate] = r }
        MPNowPlayingInfoCenter.default().nowPlayingInfo = mp
    }
    public func set(playing: Bool) { MPNowPlayingInfoCenter.default().playbackState = playing ? .playing : .paused }
}

public final class SystemRemoteCommands: RemoteCommands {
    public init() {}
    public func bind(play: @escaping () -> Void, pause: @escaping () -> Void, toggle: @escaping () -> Void,
                     skipForward: @escaping () -> Void, skipBackward: @escaping () -> Void) {
        let c = MPRemoteCommandCenter.shared()
        c.playCommand.addTarget { _ in play(); return .success }
        c.pauseCommand.addTarget { _ in pause(); return .success }
        c.togglePlayPauseCommand.addTarget { _ in toggle(); return .success }
        c.skipForwardCommand.preferredIntervals = [NSNumber(value: Player.skipSeconds)]
        c.skipForwardCommand.addTarget { _ in skipForward(); return .success }
        c.skipBackwardCommand.preferredIntervals = [NSNumber(value: Player.skipSeconds)]
        c.skipBackwardCommand.addTarget { _ in skipBackward(); return .success }
    }
}

/// Mirrors the player into the system's Now Playing and answers the media keys.
@MainActor
public final class NowPlaying {
    private let player: Player
    private let center: any NowPlayingCenter
    private var title: String?
    private var observation: Task<Void, Never>?

    public init(player: Player, center: any NowPlayingCenter = SystemNowPlayingCenter(),
                commands: any RemoteCommands = SystemRemoteCommands()) {
        self.player = player
        self.center = center
        commands.bind(
            play: { [weak self] in self?.player.play(); self?.push() },
            pause: { [weak self] in self?.player.pause(); self?.push() },
            toggle: { [weak self] in self?.player.toggle(); self?.push() },
            skipForward: { [weak self] in self?.player.skip(seconds: Player.skipSeconds); self?.push() },
            skipBackward: { [weak self] in self?.player.skip(seconds: -Player.skipSeconds); self?.push() })
        observe()
    }

    public func update(title: String?) { self.title = title; push() }

    private func push() {
        center.set(info: [
            "title": title ?? "Aloud",
            "duration": player.timeline.total.seconds,
            "elapsed": player.elapsed.seconds,
            "rate": player.isPlaying ? player.rate.factor : 0,
        ])
        center.set(playing: player.isPlaying)
    }

    /// Re-pushes whenever the player's observed state changes.
    private func observe() {
        observation = Task { [weak self] in
            while let self, !Task.isCancelled {
                await withCheckedContinuation { (c: CheckedContinuation<Void, Never>) in
                    withObservationTracking {
                        _ = self.player.isPlaying; _ = self.player.sentenceIndex; _ = self.player.rate
                    } onChange: { c.resume() }
                }
                self.push()
            }
        }
    }
}
```

`Duration.seconds` here means a `Double`; `Timeline` already has `seconds(_:)` from plan 1, so expose `extension Duration { var seconds: Double }` in `Timeline.swift` if it is not public yet.

`OutputDeviceWatcher.swift`:

```swift
import CoreAudio
import Foundation

/// Fires when the default output device changes: headphones unplugged, AirPods gone.
public final class OutputDeviceWatcher: @unchecked Sendable {
    private var address = AudioObjectPropertyAddress(
        mSelector: kAudioHardwarePropertyDefaultOutputDevice,
        mScope: kAudioObjectPropertyScopeGlobal,
        mElement: kAudioObjectPropertyElementMain)
    private let queue = DispatchQueue(label: "design.kevxu.aloud.output-device")
    private var block: AudioObjectPropertyListenerBlock?
    private var stopped = false

    public init(onChange: @escaping @Sendable () -> Void) {
        let block: AudioObjectPropertyListenerBlock = { _, _ in onChange() }
        self.block = block
        AudioObjectAddPropertyListenerBlock(AudioObjectID(kAudioObjectSystemObject), &address, queue, block)
    }

    public func stop() {
        queue.sync {
            guard !stopped, let block else { return }
            stopped = true
            AudioObjectRemovePropertyListenerBlock(AudioObjectID(kAudioObjectSystemObject), &address, queue, block)
        }
    }

    deinit { stop() }
}
```

`AppModel`: `private var nowPlaying: NowPlaying?`, `private var deviceWatcher: OutputDeviceWatcher?`; in `start()`: `nowPlaying = NowPlaying(player: player)`, `deviceWatcher = OutputDeviceWatcher { Task { @MainActor [weak self] in if self?.player.isPlaying == true { self?.player.pause(); self?.notice = "Paused: the output device changed" } } }`; `open` calls `nowPlaying?.update(title: doc.title)`.

- [ ] **Step 3: Run, check, commit**

Run: `make check && make test && make dev`: press the keyboard's play/pause key while a document is loaded; playback toggles. Unplug or switch output while playing; it pauses with a notice.

```bash
git add -A && git commit -m "speech: now playing, media keys, and the output-device pause"
```

---

### Task 6: One window and the menu-bar player

**Files:**
- Create: `Sources/Aloud/MenuBarPanel.swift`
- Modify: `Sources/Aloud/AloudApp.swift`, `Sources/Aloud/AppModel.swift`, `Sources/AloudUI/Tokens.swift`

**Interfaces:**
- Produces: `AloudApp` uses `Window("Aloud", id: "main")` instead of `WindowGroup`; `MenuBarExtra` with `isInserted: $showMenuBar` bound to `Defaults.showMenuBar` through `@AppStorage("showMenuBar")`; `MenuBarPanel(model:, openWindow:)`.
- `AppModel.currentSentenceText: String?`.

- [ ] **Step 1: Implement**

`AloudApp.body`:

```swift
    @AppStorage("showMenuBar") private var showMenuBar = true

    var body: some Scene {
        Window("Aloud", id: "main") {
            if Self.showGallery { Gallery() } else { RootView(model: model) }
        }
        .defaultSize(Size.minWindow)
        .commands { /* unchanged, plus the pasteboard group from Task 2 */ }

        MenuBarExtra(isInserted: $showMenuBar) {
            MenuBarPanel(model: model)
        } label: {
            Image(systemName: model.current == nil ? "waveform" : "waveform")
                .symbolEffect(.variableColor.iterative, isActive: model.player.isPlaying)
                .opacity(model.current == nil ? Motion.dimmed : 1)
        }
        .menuBarExtraStyle(.window)
    }
```

`Motion.dimmed: Double = 0.5` in Tokens. If `symbolEffect` does not animate in the menu bar label (say so in the report), fall back to two static symbols: `waveform` while playing and `waveform.slash` while paused, and keep the spec's "animated" as a known gap.

`MenuBarPanel.swift`:

```swift
import AloudUI
import Speech
import SwiftUI

struct MenuBarPanel: View {
    var model: AppModel
    @Environment(\.openWindow) private var openWindow
    var player: Player { model.player }

    var body: some View {
        VStack(alignment: .leading, spacing: Space.m) {
            Text(model.current?.title ?? "Nothing loaded").font(Type.cardTitle).lineLimit(1)
            Text(model.currentSentenceText ?? "Pick a document in Aloud, or press the hotkey with text on the clipboard.")
                .font(Type.caption).foregroundStyle(Ink.soft).lineLimit(Type.panelSentenceLines)
            HStack(spacing: Space.l) {
                TransportButton(.back15) { player.skip(seconds: -Player.skipSeconds) }
                TransportButton(player.isPlaying ? .pause : .play) { player.toggle() }
                TransportButton(.forward15) { player.skip(seconds: Player.skipSeconds) }
                Spacer()
                RateButton(label: player.rate.label, all: Rate.allCases.map(\.label),
                           onCycle: { model.setRate(player.rate.next) }, onPick: { model.setRate(Rate.allCases[$0]) })
            }
            .disabled(model.current == nil)
            Divider()
            Button("Open Aloud") { openWindow(id: "main"); NSApp.activate() }
            Button("Quit Aloud") { NSApp.terminate(nil) }
        }
        .padding(Space.l)
        .frame(width: Size.panelWidth)
    }
}
```

`Type.panelSentenceLines = 3`, `Size.panelWidth: CGFloat = 320` in Tokens.

`AppModel.currentSentenceText`: `player.script.sentences[safe: player.sentenceIndex]?.text` (the `safe` subscript from plan 1 lives in `ReaderView.swift`; move it to its own `Sources/Aloud/Array+Safe.swift`).

Closing the window must not stop playback: SwiftUI on macOS keeps the app running after the last window closes by default; verify by closing the window while playing.

- [ ] **Step 2: Run, look, commit**

Run: `make check && make test && make dev`: the menu-bar glyph appears; the panel shows the title and the sentence; close the window, audio continues; Open Aloud brings it back.

```bash
git add -A && git commit -m "app: one window, and the menu-bar player"
```

---

### Task 7: Global hotkey

**Files:**
- Modify: `Package.swift`, `Sources/Aloud/AloudApp.swift`, `Sources/Aloud/AppModel.swift`, `Sources/Aloud/MenuBarPanel.swift`

**Interfaces:**
- Produces: `extension KeyboardShortcuts.Name { static let pasteAndPlay }` default Ctrl+Option+Space; `AppModel.pasteAndPlay()`; `AppModel.shakeCount: Int` bumped when the clipboard has no text (the menu-bar glyph wiggles on it).

- [ ] **Step 1: Dependency**

`Package.swift`: add `.package(url: "https://github.com/sindresorhus/KeyboardShortcuts", from: "2.0.0")` and `.product(name: "KeyboardShortcuts", package: "KeyboardShortcuts")` to the `Aloud` executable's dependencies. Run `swift package resolve`; commit `Package.resolved`.

- [ ] **Step 2: Implement**

`Sources/Aloud/Hotkey.swift`:

```swift
import KeyboardShortcuts

extension KeyboardShortcuts.Name {
    static let pasteAndPlay = Self("pasteAndPlay", default: .init(.space, modifiers: [.control, .option]))
}
```

`AppModel`:

```swift
    var shakeCount = 0

    /// The hotkey: whatever text is on the clipboard becomes a note and starts playing,
    /// window or no window.
    func pasteAndPlay() {
        guard let text = NSPasteboard.general.string(forType: .string)?.trimmingCharacters(in: .whitespacesAndNewlines),
              !text.isEmpty else { shakeCount += 1; return }
        pasteNote(andPlay: true)
    }

    func installHotkey() {
        KeyboardShortcuts.onKeyUp(for: .pasteAndPlay) { [weak self] in self?.pasteAndPlay() }
    }
```

(`pasteNote` already handles the empty-clipboard notice; `pasteAndPlay` shakes instead, since the window may be closed.) `start()` calls `installHotkey()`. The `MenuBarExtra` label adds `.symbolEffect(.wiggle, value: model.shakeCount)`.

- [ ] **Step 3: Run, look, commit**

Run: `make check && make test && make dev`: copy some text, press Ctrl+Option+Space with another app in front; Aloud starts reading it. Copy nothing (clear the clipboard) and press it; the glyph shakes.

```bash
git add -A && git commit -m "app: the paste-and-play hotkey"
```

---

### Task 8: Settings

**Files:**
- Create: `Sources/Aloud/SettingsView.swift`
- Modify: `Sources/Vault/RootStore.swift`, `Tests/VaultTests/RootStoreTests.swift`, `Sources/Aloud/AloudApp.swift`, `Sources/Aloud/AppModel.swift`

**Interfaces:**
- Produces:
  - `RootStore` stores, beside each bookmark, its last known path (`vaultRootPaths: [String]`, parallel to `vaultRoots`), so an unreachable root can be named. `RootStore.Load` gains `public var unreachable: [String]` (paths). `public func replace(unreachablePath: String, with url: URL)` swaps the bookmark and starts access (the Locate action).
  - `AppModel.removeRoot(_ url: URL)`, `func locate(unreachablePath: String)`, `var unreachable: [String]`, `func setNoteFolder(_ url: URL)`, `func setLaunchAtLogin(_ on: Bool)`, `var launchAtLogin: Bool`.
  - `SettingsView(model:)` shown by a `Settings` scene.

- [ ] **Step 1: Failing tests**

Add to `RootStoreTests`:

```swift
    @Test func namesAnUnreachableRootAndLocatesIt() throws {
        let defaults = UserDefaults(suiteName: UUID().uuidString)!
        let store = RootStore(defaults: defaults)
        let gone = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: gone, withIntermediateDirectories: true)
        _ = store.add(gone)
        try FileManager.default.removeItem(at: gone)
        let load = RootStore(defaults: defaults).load()
        // A bookmark to a deleted folder may still resolve on APFS; either way the path is recorded.
        #expect(load.unreachable.count + load.urls.count == 1)
        if let path = load.unreachable.first {
            let replacement = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
            try FileManager.default.createDirectory(at: replacement, withIntermediateDirectories: true)
            RootStore(defaults: defaults).replace(unreachablePath: path, with: replacement)
            let after = RootStore(defaults: defaults).load()
            #expect(after.unreachable.isEmpty)
            #expect(after.urls.map(\.lastPathComponent) == [replacement.lastPathComponent])
        }
    }
    @Test func pathsStayParallelToBookmarks() throws {
        let defaults = UserDefaults(suiteName: UUID().uuidString)!
        let store = RootStore(defaults: defaults)
        let a = try tempDir(), b = try tempDir()
        _ = store.add(a); _ = store.add(b)
        store.remove(a)
        #expect(defaults.array(forKey: RootStore.pathsKey) as? [String] == [RootStore.key(b)])
    }
```

(`tempDir()` is whatever helper the existing file uses; match its name.)

- [ ] **Step 2: Implement RootStore changes**

Store `pathsKey = "vaultRootPaths"` alongside `key = "vaultRoots"`; `add` appends both; `remove` filters both by index; `load` collects the path for any blob that fails to resolve into `unreachable`; `replace(unreachablePath:with:)` finds the index in the paths array, writes the new bookmark and path at that index, and starts access. Migration: if `vaultRootPaths` is missing or shorter than `vaultRoots`, fill it from resolved URLs' paths and `"?"` for unresolvable blobs.

- [ ] **Step 3: SettingsView**

```swift
import AloudUI
import KeyboardShortcuts
import ServiceManagement
import Speech
import SwiftUI

struct SettingsView: View {
    @Bindable var model: AppModel
    @AppStorage("skipCode") private var skipCode = true
    @AppStorage("showMenuBar") private var showMenuBar = true

    var body: some View {
        Form {
            Section("Vault folders") {
                ForEach(model.roots, id: \.path) { url in
                    HStack {
                        Text(url.lastPathComponent)
                        if model.noteFolder == url { Text("New notes go here").font(Type.caption).foregroundStyle(Ink.soft) }
                        Spacer()
                        Button("Use for new notes") { model.setNoteFolder(url) }.disabled(model.noteFolder == url)
                        Button("Remove", role: .destructive) { model.removeRoot(url) }
                    }
                }
                ForEach(model.unreachable, id: \.self) { path in
                    HStack {
                        Label("\(URL(fileURLWithPath: path).lastPathComponent) is not reachable", systemImage: "exclamationmark.triangle")
                        Spacer()
                        Button("Locate...") { model.locate(unreachablePath: path) }
                    }
                }
                Button("Add Folder...") { model.pickRootFolder() }
            }
            Section("Voice") {
                Picker("Default voice", selection: Binding(
                    get: { model.player.voice?.id ?? "" },
                    set: { id in if let v = model.provider.voices.first(where: { $0.id == id }) { model.pickVoice(v) } })) {
                    ForEach(VoiceGroups.group(model.provider.voices, currentLanguage: Locale.current.identifier)) { g in
                        Section(g.name) { ForEach(g.voices) { v in Text(v.name).tag(v.id) } }
                    }
                }
                Picker("Default speed", selection: Binding(get: { model.player.rate }, set: { model.setRate($0) })) {
                    ForEach(Rate.allCases, id: \.self) { Text($0.label).tag($0) }
                }
            }
            Section("Reading") {
                Toggle("Skip code blocks in Markdown", isOn: $skipCode)
            }
            Section("Hotkey") {
                KeyboardShortcuts.Recorder("Paste and play:", name: .pasteAndPlay)
            }
            Section("General") {
                Toggle("Show in the menu bar", isOn: $showMenuBar)
                Toggle("Launch at login", isOn: Binding(get: { model.launchAtLogin }, set: { model.setLaunchAtLogin($0) }))
            }
        }
        .formStyle(.grouped)
        .frame(width: Size.settingsWidth)
    }
}
```

`Size.settingsWidth: CGFloat = 520` in Tokens. `AppModel.setLaunchAtLogin` uses `SMAppService.mainApp.register()` / `unregister()` and reports errors in `notice`; `launchAtLogin` reads `SMAppService.mainApp.status == .enabled`. Note: `SMAppService` works only from a bundled, signed app; under `make dev` it will report an error, which the notice shows; say so in the report and the spec (Task 11).

`setNoteFolder` writes `Defaults.noteFolderPath`. Changing `skipCode` must invalidate the current document: `AppModel` observes `Defaults.skipCode` via `NotificationCenter.default.publisher(for: UserDefaults.didChangeNotification)`; simpler: `SettingsView` calls `model.reloadCurrent()` in the toggle's `onChange`; `reloadCurrent` is `open(current, reloading: true)` if `current` is set and not editing.

`AloudApp.body` adds a third scene: `Settings { SettingsView(model: model) }`.

- [ ] **Step 4: Run, look, commit**

Run: `make check && make test && make dev`: Cmd+, opens Settings; remove and re-add a folder; change the hotkey; toggle code blocks and the open document re-extracts.

```bash
git add -A && git commit -m "app: settings, with folders that can be located and removed"
```

---

### Task 9: Raw Markdown editing, blur and Cmd+S, dirty guard

**Files:**
- Modify: `Sources/Vault/Vault.swift`, `Tests/VaultTests/VaultTests.swift`, `Sources/Aloud/ReaderView.swift`, `Sources/Aloud/ReaderTextView.swift`, `Sources/Aloud/AppModel.swift`, `Sources/Aloud/AloudApp.swift`

**Interfaces:**
- Produces: `Vault.rawText(of document: Document) throws -> String` (UTF-8, `.markdown` and `.plainText` only; PDF throws `.notEditable`). Edit mode shows the raw file text for both types, and saving writes it verbatim. `ReaderTextView` gains `onBlur: () -> Void` (the coordinator's `textDidEndEditing`). `AppModel.isDirty: Bool`.

- [ ] **Step 1: Failing test**

```swift
    @Test func rawTextIsTheFileNotTheProse() async throws {
        let root = try tempRoot()
        let vault = Vault(roots: [root])
        let url = try await vault.makeNote(text: "# Title\n\nSome *emphasis*.", in: root)
        let doc = try await vault.tree()[0].documents[0]
        #expect(try await vault.rawText(of: doc) == "# Title\n\nSome *emphasis*.")
        let pdf = Document(url: url.deletingLastPathComponent().appendingPathComponent("x.pdf"), title: "x", preview: "", modified: .now, bytes: 0, type: .pdf)
        await #expect(throws: VaultError.self) { try await vault.rawText(of: pdf) }
    }
```

- [ ] **Step 2: Implement**

`Vault.rawText(of:)`:

```swift
    public func rawText(of document: Document) throws -> String {
        guard document.type != .pdf else { throw VaultError.notEditable(document.type) }
        return try String(contentsOf: document.url, encoding: .utf8)
    }
```

`ReaderView.toggleEdit` entering edit mode: `player.pause()`, `draft = try await model.vault.rawText(of: document)` (in a `Task`; on error set `model.notice` and stay in reading mode), then `editing = true`. The Edit button is `.disabled(document.type == .pdf)` with `editButtonLabel` "Editing a PDF is not possible" for the disabled state. Leaving edit mode (Done, blur, Cmd+S) calls `save()`:

```swift
    func save() {
        Task {
            if await model.saveEdit(draft, to: document) { editing = false; model.isDirty = false }
        }
    }
```

`ReaderTextView.Coordinator` implements `textDidEndEditing(_:)` calling `parent.onBlur()`; `textDidChange` also sets `model.isDirty = true` via `onEdit`. Cmd+S: in `AloudApp.commands` add `CommandGroup(replacing: .saveItem) { Button("Save") { model.saveRequested += 1 }.keyboardShortcut("s").disabled(!model.isEditing) }` and `ReaderView` observes `model.saveRequested` with `onChange` to call `save()`.

Dirty guard: `ReaderView.onExitCommand` and the transport bar's back are fine (they are ignored while editing already); the NavigationStack back button is the remaining path. Make `ReaderView.onDisappear` save if `model.isDirty` (a save on the way out never loses text), then reset `isEditing`/`isDirty`.

Update the plan-1 spec note: Markdown editing edits the raw source now; `Task 11` writes that.

- [ ] **Step 3: Run, look, commit**

Run: `make check && make test && make dev`: edit a `.md`, see raw Markdown, change a heading, press Cmd+S, the reader re-extracts and the heading reads as changed.

```bash
git add -A && git commit -m "app: edit the raw file, save on blur and command-s, never drop a draft"
```

---

### Task 10: Live reload and the plan-1 deferrals

**Files:**
- Create: `Sources/Prose/ScriptAnchor.swift`, `Tests/ProseTests/ScriptAnchorTests.swift`
- Modify: `Sources/Aloud/AppModel.swift`, `Sources/Aloud/ReaderTextView.swift`, `Sources/AloudUI/Components/GlassBar.swift`, `Sources/Aloud/TransportBarView.swift`, `Sources/AloudUI/Components/FolderCard.swift`, `Sources/AloudUI/Components/Card.swift`, `Sources/AloudUI/Gallery.swift`

**Interfaces:**
- Produces: `public enum ScriptAnchor { public static func index(of sentenceText: String, near index: Int, in script: Script) -> Int }`: the index of the sentence with equal text nearest to `index`, else `min(index, count - 1)`, else 0.

- [ ] **Step 1: Failing tests**

```swift
import Testing
@testable import Prose

@Suite struct ScriptAnchorTests {
    func script(_ s: String) -> Script { Script(source: s, sentences: SentenceSplitter.split(s)) }
    @Test func findsTheSameSentenceAfterAnInsert() {
        let new = script("Added first. One two. Three four. Five six.")
        #expect(ScriptAnchor.index(of: "Three four.", near: 1, in: new) == 2)
    }
    @Test func prefersTheNearestOfDuplicates() {
        let new = script("Same. Other. Same. Same.")
        #expect(ScriptAnchor.index(of: "Same.", near: 3, in: new) == 3)
    }
    @Test func fallsBackToTheClampedIndex() {
        let new = script("Only one.")
        #expect(ScriptAnchor.index(of: "gone.", near: 5, in: new) == 0)
    }
}
```

- [ ] **Step 2: Implement**

```swift
import Foundation

/// Where a sentence went after the file changed underneath the reader.
public enum ScriptAnchor {
    public static func index(of sentenceText: String, near index: Int, in script: Script) -> Int {
        let matches = script.sentences.indices.filter { script.sentences[$0].text == sentenceText }
        if let best = matches.min(by: { abs($0 - index) < abs($1 - index) }) { return best }
        return max(0, min(index, script.sentences.count - 1))
    }
}
```

`AppModel.refresh()` after rebuilding `tree`: if `current` is set, not `isEditing`, and the document's `modified` in the new tree differs from `current.modified`, re-extract with `extraction.script(...)`, compute `ScriptAnchor.index(of: currentSentenceText, near: player.sentenceIndex, in: newScript)`, `let wasPlaying = player.isPlaying; player.load(newScript, at: anchored); current = newDoc; if wasPlaying { player.play() }`. Also, `open(_:)`'s short-circuit for the current document: reload when the tree's `modified` differs from `current.modified` (so reopening after an external edit is fresh).

Deferrals, each small:
- `ReaderTextView`: keyboard scrolling cancels follow. In `ClickableTextView`, override `keyDown(with:)` for page up/down, arrows and space when not editable: call `coordinator?.parent.onUserScroll()` then `super.keyDown`. Also override `scrollWheel(with:)` to call `onUserScroll` (covers trackpad momentum that `willStartLiveScroll` misses).
- `GlassBar` takes any content: change `body` to `content` with the padding and glass, no forced `HStack`; update the gallery's sample to wrap its own `HStack`; `TransportBarView` uses `GlassBar { VStack { ... } }` and drops its inline padding and `glassEffect`.
- `FolderCard` accessibility label matches the caption: `"\(name), " + (count == 0 ? "Empty folder" : "\(count) documents")`.
- `Card` label: `status.isEmpty ? title : "\(title), \(status)"`.
- `AppModel.start()` guards against running twice with `private var started = false`, and stores the `willTerminate` observer token to remove in `deinit`.
- `LibraryView` top level when `roots` is non-empty but `tree` is still empty shows a `ProgressView` for that first scan instead of an empty grid.

- [ ] **Step 3: Run, check, commit**

Run: `make check && make test && make dev`: edit the open file in another editor while playing; the reader picks up the change at the same sentence.

```bash
git add -A && git commit -m "app: the reader follows the file on disk; the deferred small things"
```

---

### Task 11: Docs and the close

**Files:**
- Modify: `docs/superpowers/specs/2026-09-09-aloud-design.md`, `README.md`

- [ ] **Step 1: Spec edits** (one sentence per line, no em dash)

- Reader section: replace the plan-1 note "Editing a Markdown file edits its raw source, not the extracted prose; v1's first plan restricts Edit to plain text until the raw-source editor lands." with "Edit shows the raw file for `.md` and `.txt` and writes it back verbatim; Done, blur and Cmd+S all save, and leaving the reader with a dirty draft saves on the way out."
- Library section: after the Cmd+V sentence add "Cmd+Shift+V does the same from anywhere in the app, since bare Cmd+V reaches the library only when it has focus."
- Menu-bar section: if the glyph could not animate in the label, add "The glyph is static in this build: `waveform` while speaking and `waveform.slash` while paused."
- Settings section: add "Launch at login is registered through `SMAppService` and takes effect only in the signed, bundled build."
- Speech section: after the output-device sentence add "The pause posts a notice so a listener knows why the voice stopped."
- Tooling: add "Xcode 26 is now required to run the sandboxed build: `xcodegen generate`, open `Aloud.xcodeproj`, sign with your team."

- [ ] **Step 2: README**: list the new features in one paragraph and the Xcode step.

- [ ] **Step 3: Full pass**: `make check && make test && make dev`; walk the spec's Library, Reader, Transport bar, Voice popover, Menu-bar item and Settings sections against the app and list any sentence that is still unimplemented in the report (a gap to report, not fix).

```bash
git add -A && git commit -m "docs: v1 complete"
```

---

### Task 12: The landing state and the docked transport bar

**Files:**
- Modify: `Sources/AloudUI/Components/EmptyState.swift`, `Sources/AloudUI/Components/GlassBar.swift`, `Sources/AloudUI/Gallery.swift`, `Sources/AloudUI/Tokens.swift`, `Sources/Aloud/RootView.swift`, `Sources/Aloud/TransportBarView.swift`, `Sources/Aloud/LibraryView.swift`, `Tests/AloudUITests/GalleryTests.swift`

**Interfaces:**
- Produces: `EmptyState(kind: EmptyState.Kind, onPrimary:, onSecondary:)` with `public enum Kind { case noVault, emptyVault }`; `GlassBar(docked: Bool = false)`; the transport bar always present.

Kevin's request: "we need a better empty landing state. Also make sure the play bar is always at the bottom."

- [ ] **Step 1: Tokens**

Add to `Tokens.swift`: `Size.landingGlyph: CGFloat = 96`, `Size.landingMeasure: CGFloat = 420`, `Type.landingTitle = Font.largeTitle.weight(.semibold)`, `Type.landingBody = Font.title3`, `Ink.landingGlyph = Color.accentColor`, `Radius.dockedTop = Radius.l`.

- [ ] **Step 2: EmptyState fills the window**

```swift
public struct EmptyState: View {
    public enum Kind { case noVault, emptyVault }
    let kind: Kind
    let onPrimary: () -> Void
    let onSecondary: () -> Void
    public init(kind: Kind, onPrimary: @escaping () -> Void, onSecondary: @escaping () -> Void) { ... }
    var body: some View {
        VStack(spacing: Space.xl) {
            Image(systemName: "waveform")
                .resizable().scaledToFit()
                .frame(width: Size.landingGlyph, height: Size.landingGlyph)
                .foregroundStyle(Ink.landingGlyph)
                .accessibilityHidden(true)
            Text("Aloud").font(Type.landingTitle)
            Text(kind == .noVault
                 ? "Point it at a folder of notes, or paste anything, and listen."
                 : "This folder has no .md, .txt or .pdf files yet.")
                .font(Type.landingBody).foregroundStyle(Ink.soft)
                .multilineTextAlignment(.center)
                .frame(maxWidth: Size.landingMeasure)
            HStack(spacing: Space.m) {
                Button(kind == .noVault ? "Choose a folder" : "Import files", action: onPrimary).buttonStyle(.glassProminent)
                Button("Paste from clipboard", action: onSecondary).buttonStyle(.glass)
            }
            Text("Drop files or folders anywhere in this window. Ctrl+Option+Space reads the clipboard from any app.")
                .font(Type.caption).foregroundStyle(Ink.soft)
                .multilineTextAlignment(.center)
                .frame(maxWidth: Size.landingMeasure)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .padding(Space.xxxl)
    }
}
```

The hint's hotkey text should read the current shortcut; `AloudUI` cannot see KeyboardShortcuts, so `EmptyState` takes `hotkey: String` in its init and the app passes `KeyboardShortcuts.getShortcut(for: .pasteAndPlay)?.description ?? "Ctrl+Option+Space"`.

`LibraryView`: `roots.isEmpty` shows `.noVault` (primary = `pickRootFolder`, secondary = `pasteNote`); a scanned tree with zero documents anywhere (`model.allDocuments(in: tree).isEmpty`) at the top level shows `.emptyVault` (primary = `pickFilesToImport`, secondary = `pasteNote`).

- [ ] **Step 3: Transport bar always present and docked**

`GlassBar(docked:)`: when `docked`, the glass shape is `.rect(topLeadingRadius: Radius.dockedTop, topTrailingRadius: Radius.dockedTop)` (bottom corners square), no horizontal inset. `RootView`'s `safeAreaInset(edge: .bottom)` always shows `TransportBarView` (no `if model.current != nil`), with no outer padding so the bar sits flush to the bottom and spans the width; the bar's own padding stays inside.

`TransportBarView` when `model.current == nil`: controls `.disabled(true)`, the title slot shows "Nothing loaded" in `Ink.soft`, the scrubber shows `0:00` and `~0:00` at progress 0. `Player.elapsed`/`remaining` already return zero for an empty script; check `progress` is 0 and not NaN.

- [ ] **Step 4: Gallery and test**

Gallery shows both `EmptyState` kinds and `GlassBar(docked: true)`; `GalleryTests.sections` count still holds.

- [ ] **Step 5: Run, look, commit**

`make check && make test && make dev`: with no vault the landing fills the window and the bar sits at the bottom, disabled; add a vault and the bar stays put.

```bash
git add -A && git commit -m "app: a landing that fills the window, and a transport bar that is always at the bottom"
```

---

## Self-review

**Spec coverage against plan-2 scope:** PDF (T1); paste, drop, import, `+` menu, empty-state paste (T2); search, list toggle, right-click with Play/Mark finished/Reveal/Delete (T3); voice popover with preview, quality tag, Get more voices, voice fallback notice, remembered voice and rate (T4); Now Playing, media keys, output-device pause (T5); menu-bar item, closing the window keeps playing, Open Aloud (T6); hotkey with empty-clipboard shake (T7); Settings: folders add/remove/default/Locate, default voice and rate, hotkey recorder, skip code, launch at login, show menu bar (T8); raw editing, save on blur and Cmd+S, dirty guard (T9); data-flow item 5 live reload, plan-1 minors (T10); docs (T11). Not covered and stated: the "In progress" status for a started document that is not current stays as is (the spec's `m:ss left` needs an extraction the library does not have); "grid/list toggle" is T3.

**Type consistency:** `Defaults.*` keys match the `@AppStorage` strings used in `LibraryView` (`listView`), `AloudApp` (`showMenuBar`), `SettingsView` (`skipCode`, `showMenuBar`). `AppModel.setRate(_:)` and `pickVoice(_:)` are the only writers of rate and voice. `SourceKind(_ type: DocumentType)` replaces both ternaries. `NowPlaying` uses `player.timeline.total.seconds`, which requires `Duration.seconds` public in `Timeline.swift`. `Player.onVoiceUnavailable` set in `AppModel.init`. `ScriptAnchor.index(of:near:in:)` used by `refresh`.

**Placeholders:** none; every step has code or an exact edit.
