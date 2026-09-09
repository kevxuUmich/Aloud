# Aloud - design

Aloud is a macOS app that reads your text files aloud.
It is for people who take in more by listening than by reading: multitaskers, busy people, and anyone whose chat transcripts and notes have grown past what they want to read.
It points at folders you already have, like Obsidian does, and plays them with the voices already on the Mac.

Working name.
The repo is `~/aloud`, the app target is `Aloud`, the bundle id is `design.kevxu.aloud`.

## Scope of v1

In:

- macOS 26 only, SwiftUI, Liquid Glass materials and system controls.
- Vault folders: read `.md`, `.txt` and `.pdf` in place, watch for changes, never copy.
- Paste-to-note: Cmd+V in the library, drop onto the window, and a global hotkey that reads the clipboard and starts playing.
- Apple system voices through `AVSpeechSynthesizer`, with rate control.
- Sentence and word highlight that follows the voice, click-to-seek on a sentence.
- Remembered position per document, marked Finished at the end.
- A persistent transport bar, a voice popover, a menu-bar player, and a Settings window.
- Edit `.md` and `.txt` in the reader.

Out, with the seam that admits it later:

- Cloud voices, behind the `VoiceProvider` protocol.
- Web pages, `.docx`, `.epub`, behind the `Extractor` protocol.
- iOS, as a second app target on the same packages.
- Sync of progress across machines.
- Any payment, account, or telemetry.

## Architecture

One Swift package with four library targets and one thin app.
Each library has one purpose and its own test target.
Every rule about text, timing or geometry lives in a library, so it is tested from the terminal with `swift test` and the app only draws.
Swift 6 language mode with strict concurrency, so a data race is a compile error rather than a bug report.

### `Vault`

The folders the user pointed at, and what is in them.

- Stores each root as a security-scoped bookmark in the app's own storage, resolves them on launch, and drops any that no longer resolve with a visible notice rather than silently.
- Walks each root for `.md`, `.txt` and `.pdf`, ignoring dot-files and dot-folders, and exposes a tree of `Folder` and `Document` values.
- A `Document` carries its URL, title, modified date, size and type.
- Watches every root recursively with FSEvents at 300 ms latency, since `DispatchSource` watches one directory and not its children, and republishes the tree on change.
- Writes new notes: `makeNote(text:in:)` writes `<first line, sanitised, max 60 chars>.md` into the chosen folder, appending ` 2`, ` 3` on collision.
- Writes edits: `save(text:to:)` for `.md` and `.txt` only, atomic write, and refuses PDF.
- Knows nothing about speech or progress.

### `Prose`

Turns a file into spoken text.

- `Extractor` is a protocol with one requirement, `func script(from data: Data, type: DocumentType) throws -> Script`.
- `Script` is an array of `Sentence`, each with its text and its range back in the displayed source, plus the displayed source string itself.
- Parsing is not written here.
Markdown is parsed by Apple's `swift-markdown` (cmark-gfm underneath, Apache-2.0), PDF text comes from the system's PDFKit, and sentences come from `SentenceSplitter`.
What this target owns is only the rules that turn a parse into speech, each a short function over someone else's output.
- `MarkdownExtractor`: a `MarkupWalker` over the `swift-markdown` tree.
Headings become their own sentences, list markers are dropped, link text is kept and the URL dropped, emphasis is dropped, images are dropped, tables are read row by row with cells separated by commas, code blocks are replaced by the single sentence "Code block." when the skip setting is on and read verbatim when it is off, front matter between `---` fences is dropped.
- `PlainTextExtractor`: paragraphs split on blank lines, sentences split by `SentenceSplitter`.
- `PDFExtractor`: `PDFPage.string` page by page, then a cleanup pass that joins a line ending in a hyphen with the next, drops any line that appears on more than half the pages (running headers and footers), drops bare page numbers, and collapses single line breaks inside a paragraph.
If PDFKit's reading order proves poor on real documents, `pdf_oxide` (Rust, MIT/Apache, Swift bindings, sub-millisecond per document) is the named replacement behind the same `Extractor` protocol; it is not taken now because it means shipping a prebuilt binary.
- Extraction runs off the main actor and its result is cached per file, keyed by path and modification date, so reopening a document is instant and the library's thumbnails and estimates are computed once.
- Sentence splitting is `SentenceSplitter`'s rule everywhere, terminal punctuation followed by whitespace with an abbreviation guard, so the three extractors agree on what a sentence is; `NLTokenizer` was tried first and does not split before a lowercase sentence start, which is how most pasted text reads.
- `estimate(_ script: Script, rate: Float) -> Duration` uses 160 words per minute at rate 1.0, scaled linearly, and is what every "~8 min" label reads.
- Pure functions, no I/O, the most thoroughly tested target.

### `Speech`

Wraps `AVSpeechSynthesizer` and is the only thing that talks to it.

- `VoiceProvider` is a protocol: list voices, speak one sentence with a rate and voice, report word ranges as they are spoken, stop.
- `AppleVoiceProvider` is the v1 implementer.
- `Player` takes a `Script`, speaks sentence by sentence, and publishes `sentenceIndex`, `wordRange`, `isPlaying`, `rate`, `voice`, `elapsed`, `remaining`.
- Speaking per sentence rather than as one utterance is what makes seek, rate change and voice change take effect at the next sentence boundary instead of the end of the file.
- `skip(seconds:)` converts seconds to a sentence count from the estimate and lands on a sentence boundary, so back 15 s is never mid-word.
- Rate maps the UI's `1.0x` to `AVSpeechUtteranceDefaultSpeechRate` and scales from there; the allowed steps are 0.75, 1, 1.25, 1.5, 1.75, 2, 2.5, 3.
- Voices are grouped by language, current system language first, and each carries a quality tag from `AVSpeechSynthesisVoiceQuality`.
- Registers with `MPNowPlayingInfoCenter` and `MPRemoteCommandCenter`, so keyboard media keys, AirPods and the Now Playing widget work.
- Pauses itself when the default output device changes or disappears, observed through CoreAudio's default-device property listener; macOS has no `AVAudioSession`.
- The pause posts a notice so a listener knows why the voice stopped.
- A voice that is no longer installed falls back to the system voice and posts a notice naming the voice that went.
- Previewing a voice stops the utterance in the air and leaves the reader on the same sentence, so Play speaks it again from its start.

### `AloudUI`

The design system and the components, and nothing that knows about vaults or speech.
It is the stylesheet, in Swift.

- `Tokens.swift` is the one file where a number or a colour is written down: the spacing scale (4, 8, 12, 16, 24, 32, 48), the radii, the type ramp as named text styles, semantic colours (`ink`, `inkSoft`, `accent`, `highlightSentence`, `highlightWord`), the glass materials, and the motion durations and curves.
- `Components/` has one file per component, each a view with a small, typed API and no literals: `GlassBar`, `Card`, `FolderCard`, `IconButton`, `TransportButton`, `RateButton`, `Scrubber`, `VoiceRow`, `EmptyState`, `Notice`.
- `Modifiers/` has the shared button styles and the highlight style.
- `Gallery.swift` renders every component in every state on one scrolling page, the storybook.
The app opens it with `aloud --gallery`, and it is where a component is designed before it is placed.
- A test greps `AloudUI` and `AloudApp` for literal paddings, sizes, colours and durations outside `Tokens.swift` and fails on any, so the tokens stay the only source.

### `AloudApp`

SwiftUI, thin, composed from `AloudUI`.

- One `AppModel` owns the `Vault`, one `Player`, the progress store, and the current `Document`.
- The window scene and the menu-bar scene both read the same `AppModel`, so they can never disagree.
- Progress store: a JSON file in Application Support keyed by file path, holding `sentenceIndex`, `finished` and `lastPlayed`; it is never written into the user's files.
- Global hotkey through `KeyboardShortcuts` (sindresorhus, MIT), which wraps `RegisterEventHotKey`, needs no Accessibility permission, and ships the recorder control the Settings window uses; default `Ctrl+Option+Space`.
- On the hotkey: read `NSPasteboard.general` as string, make a note in the default vault folder, load it, play.
- If the clipboard has no text, the menu-bar glyph shakes once and nothing else happens.

## Surfaces

### Window

One window, minimum 720 x 480, standard macOS 26 window background material, toolbar in glass.
Light and dark follow the system.
Font is the system font throughout.

### Library

A grid of the current folder.

- Folders first, then documents by modified date, newest first.
- A document card is a small monospaced render of the file's first lines, the title, and one status line: `~8 min` before it is started, `3:12 left` once started, `Finished` when done.
- The pre-start estimate reads the file's byte count at one word per six bytes of file size, since only the first 600 bytes are read at scan time.
- Title is the first Markdown heading if any, else the first non-empty line, truncated to two lines in the card.
- A folder card shows its name and its document count.
- Toolbar: back when inside a folder, search field filtering by title and body, a `+` menu with New note from clipboard, Import files, Add vault folder, and a grid/list toggle.
- Dropping files or folders onto the window copies files into the current vault folder and adds folders as new roots after asking which.
- Cmd+V with no text field focused creates a note from the clipboard and opens it.
- Cmd+Shift+V does the same from anywhere in the app, since bare Cmd+V reaches the library only when it has focus.
- Right-click on a card: Play, Mark finished, Reveal in Finder, Delete (moves to Trash).
- A vault folder is removed from the `+` menu while it is on screen, or by right-clicking its card at the top level, and only the link goes: its files are not touched.
- The empty landing fills the window: the waveform glyph, "Aloud", one sentence, the two buttons "Choose a folder" and "Paste from clipboard", and a hint that files can be dropped anywhere in the window and that the hotkey reads the clipboard from any app.
- A vault that has been added but holds nothing readable shows the same landing with "Import files" in place of "Choose a folder".
- The transport bar is there behind both landings, since it is the app's one transport and a control that appears only once something is loaded is a control nobody learns.

### Reader

Pushed from the library, title in the toolbar.

- The extracted prose at about 68 characters measure, generous leading, system font, A/A stepper in the toolbar across five sizes that persist.
- The spoken sentence gets a soft accent-tinted highlight, the spoken word a stronger one.
- Click on a sentence seeks to it and, if paused, starts playing.
- Auto-scroll keeps the spoken sentence in the upper third; a manual scroll disables following until play is pressed or a sentence is clicked.
- Edit button turns the body into a plain text editor for `.md` and `.txt`, saved atomically on blur or Cmd+S, and playback stops while editing; PDFs show Edit disabled with a tooltip.
- Edit shows the raw file for `.md` and `.txt` and writes it back verbatim; Done, blur and Cmd+S all save, and leaving the reader with a dirty draft saves on the way out.
- A save that fails on the way out keeps the draft on the model until that document is opened for editing again, so nothing is lost with the view gone.
- Saves are serialized per document, so a blur and the Done click that follows it write once.
- Mark finished toggles the progress flag and is what the library's `Finished` reads.
- Escape or the back button returns to the library without stopping playback.

### Transport bar

A glass bar docked flush to the bottom edge of the window and the full width of it, on both the library and the reader.

It is always present, from first launch onward; with nothing loaded the scrubber and the transport controls are disabled and the title slot reads "Nothing loaded", and the voice button stays enabled so a listener can hear the voices before opening anything.

- Row one: elapsed, a scrubber that seeks by sentence, remaining as `~m:ss`.
- Row two, left: the rate button showing `1x`; click cycles the steps, right-click shows them all.
- Row two, centre: back 15 s, play/pause, forward 15 s.
- Row two, right: the voice button, showing the voice name, opening the voice popover.
- The row is three columns: the title at the left, the transport at the true centre, the speed and the voice at the right, so the cluster stays centred however long the title is.
- In the library the bar also shows the playing title, and clicking it opens the reader.
- Space toggles play/pause anywhere a text field is not focused; left and right arrows skip 15 s.

### Voice popover

- Voices grouped by language, current system language first.
- Each row: a preview button that speaks one fixed sentence in that voice, the name, the region, and the quality tag.
- Picking a voice takes effect at the next sentence.
- "Get more voices" opens System Settings at Accessibility, Spoken Content, since only the system can install voices.
- A search field at the top filters by voice name, language, region and quality.
- The installed set is read again every time the popover opens, so a voice downloaded while Aloud is running appears without a restart.
- The popover says that Siri voices are not available to apps, since that is the first thing a reader looks for and the one thing that can never be in the list.

### Menu-bar item

- A waveform glyph, animated while speaking, still when paused, dimmed when nothing is loaded.
- The glyph is `waveform` and animates with `variableColor` while speaking; if that does not animate in the status item, the fallback is a static `waveform.slash` while paused.
- Click opens a small glass panel: title, the sentence being spoken, back 15 s, play/pause, forward 15 s, the rate button, and Open Aloud.
- Closing the window does not stop playback; Quit does.
- The hotkey's paste-and-play works with the window closed.

### Settings

Vault folders (add, remove, choose the default for new notes), default voice, default rate, hotkey, whether code blocks are skipped, launch at login, and whether the menu-bar item is shown.

A root whose bookmark will not resolve is listed by its last known path with Locate and Remove, rather than dropped, since the volume may only be unmounted.
Launch at login is registered through `SMAppService` and takes effect only in the signed, bundled build.

## Data flow

1. Launch resolves the bookmarks, walks the roots, restores the last document from the progress store into the player, paused.
2. Opening a document reads its data, runs the matching `Extractor`, and hands the `Script` to the `Player` at the stored `sentenceIndex`.
3. The `Player` publishes indices; the reader maps them to ranges through the `Script` for highlight and scroll.
4. Every sentence boundary writes `sentenceIndex` to the progress store, debounced at 1 s; the last sentence sets `finished`.
5. A file change under a root re-walks the tree; if the open document changed on disk and is not being edited, it is re-extracted and playback resumes at the same sentence text where it still exists, else at the nearest index.
6. A save from the editor triggers one reload through the same path, anchored at the current sentence.

## Error handling

- A bookmark that fails to resolve is listed in Settings as "Folder not reachable" with a Locate button, and its cards are hidden rather than shown broken.
- A file that fails to read or extract shows its card with a warning glyph and the error in a tooltip; clicking it shows the error in the reader in place of the body.
- An encrypted or image-only PDF yields an empty `Script`, which the reader reports as "This PDF has no text to read".
- A voice that disappears (deleted in System Settings) falls back to the system default voice at the next sentence and shows a one-line notice in the transport bar.
- Writes to the vault that fail surface as an alert and keep the text in the editor so nothing is lost.
- Nothing is logged to disk except through `os.Logger`.

## Testing

- `Prose` is the heart of the suite: fixture files for each extractor with expected sentence arrays, the PDF cleanup rules each pinned by a fixture that would fail without them, and the duration estimate at every rate step.
- `Vault` is tested against a temporary directory: walk, ignore rules, note naming and collision, atomic save, watch-and-republish with a real file write.
- `Speech` is tested through a fake `VoiceProvider` that records what it was asked to speak, so seek, rate steps, skip-to-boundary and the finished transition are verified without audio.
- `AloudUI` has the literal-lint test and a smoke test that the gallery builds every component.
- `AloudApp` has no logic worth testing on its own; anything that grows there moves down into a library.
- UI is checked by hand at each milestone, per the standing rule that motion and rendering are verified in unit tests where they can be and by eye where they cannot.

## Dependencies

Chosen for being local, fast and small; each one is a thing not worth writing.

| Need | Choice | Why |
|---|---|---|
| Markdown parsing | `swift-markdown` (Apple, Apache-2.0) | cmark-gfm in C underneath, spec-complete, a visitor API that makes the speech walker about eighty lines |
| PDF text | PDFKit (system) | zero dependency; `pdf_oxide` is the named fallback |
| Sentence splitting | `Prose.SentenceSplitter` (ours) | punctuation rule with an abbreviation guard; `NLTokenizer` does not split before a lowercase start |
| Speech | `AVSpeechSynthesizer` (system) | instant, offline, word timing for free |
| Global hotkey | `KeyboardShortcuts` (sindresorhus, MIT) | Carbon hotkeys without the Carbon, plus the recorder UI; pinned to 1.15.0 while the machine has only the command-line tools, since 1.16 and later carry `#Preview` blocks that need Xcode's macro plugin; move to 2.x once Xcode is installed |
| Project generation | XcodeGen (dev only) | no `.pbxproj` in git |
| File watching for dev | `watchexec` (brew, dev only) | the rebuild loop |

Looked at and not taken: `SwiftText` (wraps PDFKit, needs Swift 6.3 and the toolchain here is 6.2), `Ink` and `Down` (slower or less complete than `swift-markdown`), `mlx-audio-swift` (MIT, macOS 14+, streaming, thirteen on-device models; it is the obvious first cloud-free implementer of `VoiceProvider` in a later version, not in v1 because it means model downloads in the hundreds of megabytes and a GPU warm-up before the first word).

## Tooling and the dev loop

There is no `npm run dev` in Swift; the closest thing is built here as a `Makefile`.

- `make dev` builds with `swift build`, assembles `.build/Aloud.app` from the binary plus `Info.plist`, and relaunches it.
Under two seconds for an incremental change.
- `make watch` runs `make dev` on every save through `watchexec`.
This is the `npm run dev`.
- `make gallery` is `make dev` with `--gallery`, opening the component page instead of the library, for design work in isolation.
- `make test` is `swift test`; `make check` is `swift format lint` plus `swift build`; both are what a commit is gated on.
- Everything above works with the command-line tools alone, which is what is installed today.
- On a machine with only the command-line tools, `make test` passes the framework search path for `Testing.framework` explicitly; Xcode removes the need.
- `Aloud --say <file>` speaks a file from the terminal, and `Aloud --silent` runs with the fake voice, so the UI can be worked on without a word being spoken.
- Xcode 26 is needed for signing, the asset catalog, SwiftUI previews and shipping the `.app`; `project.yml` is checked in and `xcodegen` produces the project when it is installed.
- The Xcode step is required for the sandboxed build and for `SMAppService`: `xcodegen generate`, open `Aloud.xcodeproj`, sign with your team.
Hot reload inside a running app (InjectionNext) is an Xcode-era addition and not part of v1.
- Sandboxed, with the user-selected-file read-write entitlement and bookmark entitlements.
- Distribution and pricing are not part of this spec.

## Performance

- `@Observable` models, so a view re-renders only for the properties it read.
- The library grid is `LazyVGrid`; thumbnails and estimates come from the extraction cache and are rendered once per file version.
- The reader body is one `Text` built from an `AttributedString`, with the sentence and word highlights applied as attribute runs, never one view per word.
- Extraction and file walking run on a background actor; the main actor only receives finished values.
- File watching is debounced so a save that writes twice re-walks once.
- Speech is per sentence, so the synthesizer holds one utterance at a time and a rate or voice change costs nothing.

## Milestones

1. `Makefile`, `Package.swift`, an empty app that opens a window, `make watch` proven.
2. `AloudUI`: tokens, components, gallery, the literal-lint test.
3. `Prose` and `Vault`, tested, no UI.
4. `Speech` with the fake provider tested, then the Apple provider speaking a fixture from `aloud --say <file>`.
5. App: library and reader with the transport bar, one vault folder, `.md` and `.txt`.
6. PDF, paste-to-note, drop, search, progress and Finished.
7. Voice popover, menu-bar player, hotkey, Settings, Now Playing.
