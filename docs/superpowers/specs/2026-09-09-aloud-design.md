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

One Swift package with three library targets and one thin app.
Each library has one purpose and its own test target.
Every rule about text, timing or geometry lives in a library, so it is tested from the terminal with `swift test` and the app only draws.

### `Vault`

The folders the user pointed at, and what is in them.

- Stores each root as a security-scoped bookmark in the app's own storage, resolves them on launch, and drops any that no longer resolve with a visible notice rather than silently.
- Walks each root for `.md`, `.txt` and `.pdf`, ignoring dot-files and dot-folders, and exposes a tree of `Folder` and `Document` values.
- A `Document` carries its URL, title, modified date, size and type.
- Watches every root with `DispatchSource` file-system events, debounced at 300 ms, and republishes the tree on change.
- Writes new notes: `makeNote(text:in:)` writes `<first line, sanitised, max 60 chars>.md` into the chosen folder, appending ` 2`, ` 3` on collision.
- Writes edits: `save(text:to:)` for `.md` and `.txt` only, atomic write, and refuses PDF.
- Knows nothing about speech or progress.

### `Prose`

Turns a file into spoken text.

- `Extractor` is a protocol with one requirement, `func script(from data: Data, type: DocumentType) throws -> Script`.
- `Script` is an array of `Sentence`, each with its text and its range back in the displayed source, plus the displayed source string itself.
- `MarkdownExtractor`: strips syntax, headings become their own sentences, list markers are dropped, link text is kept and the URL dropped, emphasis markers are dropped, images are dropped, tables are read row by row with cells separated by commas, fenced and indented code blocks are replaced by the single sentence "Code block." when the skip setting is on and read verbatim when it is off, front matter between `---` fences is dropped.
- `PlainTextExtractor`: paragraphs split on blank lines, sentences split by `NLTokenizer`.
- `PDFExtractor`: text from PDFKit page by page, then a cleanup pass that joins a line ending in a hyphen with the next, drops any line that appears on more than half the pages (running headers and footers), drops bare page numbers, and collapses single line breaks inside a paragraph.
- Sentence splitting uses `NLTokenizer(unit: .sentence)` everywhere, so the three extractors agree on what a sentence is.
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

### `AloudApp`

SwiftUI, thin.

- One `AppModel` owns the `Vault`, one `Player`, the progress store, and the current `Document`.
- The window scene and the menu-bar scene both read the same `AppModel`, so they can never disagree.
- Progress store: a JSON file in Application Support keyed by file path, holding `sentenceIndex`, `finished` and `lastPlayed`; it is never written into the user's files.
- Global hotkey with `RegisterEventHotKey`, which needs no Accessibility permission; default `Ctrl+Option+Space`, changeable.
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
- Title is the first Markdown heading if any, else the first non-empty line, truncated to two lines in the card.
- A folder card shows its name and its document count.
- Toolbar: back when inside a folder, search field filtering by title and body, a `+` menu with New note from clipboard, Import files, Add vault folder, and a grid/list toggle.
- Dropping files or folders onto the window copies files into the current vault folder and adds folders as new roots after asking which.
- Cmd+V with no text field focused creates a note from the clipboard and opens it.
- Right-click on a card: Play, Mark finished, Reveal in Finder, Delete (moves to Trash).
- First-launch empty state is one glass panel with two actions, "Pick a folder to read from" and "Paste anything", and nothing else.

### Reader

Pushed from the library, title in the toolbar.

- The extracted prose at about 68 characters measure, generous leading, system font, A/A stepper in the toolbar across five sizes that persist.
- The spoken sentence gets a soft accent-tinted highlight, the spoken word a stronger one.
- Click on a sentence seeks to it and, if paused, starts playing.
- Auto-scroll keeps the spoken sentence in the upper third; a manual scroll disables following until play is pressed or a sentence is clicked.
- Edit button turns the body into a plain text editor for `.md` and `.txt`, saved atomically on blur or Cmd+S, and playback stops while editing; PDFs show Edit disabled with a tooltip.
- Mark finished toggles the progress flag and is what the library's `Finished` reads.
- Escape or the back button returns to the library without stopping playback.

### Transport bar

A glass bar across the bottom of both the library and the reader, shown from the first time a document is loaded in the session.

- Row one: elapsed, a scrubber that seeks by sentence, remaining as `~m:ss`.
- Row two, left: the rate button showing `1x`; click cycles the steps, right-click shows them all.
- Row two, centre: back 15 s, play/pause, forward 15 s.
- Row two, right: the voice button, showing the voice name, opening the voice popover.
- In the library the bar also shows the playing title, and clicking it opens the reader.
- Space toggles play/pause anywhere a text field is not focused; left and right arrows skip 15 s.

### Voice popover

- Voices grouped by language, current system language first.
- Each row: a preview button that speaks one fixed sentence in that voice, the name, the region, and the quality tag.
- Picking a voice takes effect at the next sentence.
- "Get more voices" opens System Settings at Accessibility, Spoken Content, since only the system can install voices.

### Menu-bar item

- A waveform glyph, animated while speaking, still when paused, dimmed when nothing is loaded.
- Click opens a small glass panel: title, the sentence being spoken, back 15 s, play/pause, forward 15 s, the rate button, and Open Aloud.
- Closing the window does not stop playback; Quit does.
- The hotkey's paste-and-play works with the window closed.

### Settings

Vault folders (add, remove, choose the default for new notes), default voice, default rate, hotkey, whether code blocks are skipped, launch at login, and whether the menu-bar item is shown.

## Data flow

1. Launch resolves the bookmarks, walks the roots, restores the last document from the progress store into the player, paused.
2. Opening a document reads its data, runs the matching `Extractor`, and hands the `Script` to the `Player` at the stored `sentenceIndex`.
3. The `Player` publishes indices; the reader maps them to ranges through the `Script` for highlight and scroll.
4. Every sentence boundary writes `sentenceIndex` to the progress store, debounced at 1 s; the last sentence sets `finished`.
5. A file change under a root re-walks the tree; if the open document changed on disk and is not being edited, it is re-extracted and playback resumes at the same sentence text where it still exists, else at the nearest index.

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
- `AloudApp` has no logic worth testing on its own; anything that grows there moves down into a library.
- UI is checked by hand at each milestone, per the standing rule that motion and rendering are verified in unit tests where they can be and by eye where they cannot.

## Tooling

- One `Package.swift` for the three libraries and their tests; `swift build` and `swift test` work with the command-line tools alone, which is what is installed today.
- The app target is generated by XcodeGen from `project.yml`, so no hand-maintained `.pbxproj` is checked in.
- Xcode 26 is needed for signing, the asset catalog and running the `.app`, and is installed when the app target is first built.
- Sandboxed, with the user-selected-file read-write entitlement and bookmark entitlements.
- Distribution and pricing are not part of this spec.

## Milestones

1. `Prose` and `Vault`, tested, no UI.
2. `Speech` with the fake provider tested, then the Apple provider speaking a fixture from a command-line harness.
3. App: library and reader with the transport bar, one vault folder, `.md` and `.txt`.
4. PDF, paste-to-note, drop, search, progress and Finished.
5. Voice popover, menu-bar player, hotkey, Settings, Now Playing.
