# Clipboard panel - design

The global hotkey today reads the clipboard, writes it into the default folder as a note, and starts speaking, with nothing on screen to say what it took or to let the listener decide.
This changes the hotkey into a preview: a small floating panel under the menu bar that shows what is on the clipboard and offers to play it.
Nothing is written until Play.

The system's own Now Playing card, the one in the menu bar's Control Center, cannot be opened by an app and only appears once something is playing.
It stays what it already is, a mirror of Aloud's player, and this design makes the mirror worth looking at.

## What the listener sees

Pressing the hotkey in any app, window open or closed:

- A panel appears centred under the menu bar on the display that holds the menu bar, so on a MacBook it hangs under the notch.
- It does not take focus. The app in front stays in front, and its window stays key.
- Layout mirrors the Now Playing card: a square glyph plate at the left, the title and a subtitle at the right, transport under them, a scrubber under that.
- Before Play, the title is the clipboard's first line as `Title.from(text:fallback:)` names a note, the subtitle is `From clipboard · ~3 min · 412 words`, the glyph plate carries the waveform, and the transport shows Play alone enabled with the scrubber empty.
- Play writes the note, opens it and speaks, exactly as `pasteNote(text:andPlay:)` does today. The panel stays and becomes a mini player: play/pause, back 15 s, forward 15 s, the scrubber, elapsed and remaining, all bound to the one `Player`.
- Text that was pasted before is the note it became: Play opens and plays that note rather than writing a numbered second file.
The check reads only the files the text would have been named, the title's own name and its numbered siblings, and compares their whole contents, so a note edited since it was pasted is left as its own.
The window's Cmd+Shift+V goes through the same path.
- Enter or Space plays. Escape dismisses. A click anywhere outside dismisses. Dismissing before Play leaves nothing behind; dismissing after Play leaves the note and keeps playing, since the transport bar and the menu-bar item already carry the player.
- The hotkey while the panel is open: if the clipboard's text differs from the previewed text, the preview swaps to the new text and the transport returns to the before-Play state without touching the current player. If it is the same text, the panel stays as it is. If the panel is already a player for that text, the panel stays and the reading pauses.
- The hotkey after the panel was dismissed, with the played note's text still on the clipboard and the note still loaded: the panel comes back as the note's player, and the reading pauses.
It is not a preview, which would say the note has not started and would write it a second time.
Different text is a preview, as above, and the player is left alone.
- With no text on the clipboard, the panel opens with the title `Nothing to read` and the subtitle `The clipboard has no text`, transport disabled, and dismisses itself after `Motion.emptyPanelHold`. The menu-bar glyph no longer shakes, since the miss now has a place to be reported. `shakeCount` and its `.wiggle` effect are removed.
- With no default folder, Play cannot write, so the subtitle reads `Pick a folder in Aloud first` and Play opens the main window instead. This is today's `Pick a folder to read from first` notice, moved onto the panel.

## What the system card shows

`NowPlaying.push` publishes the title alone today.
It grows a subtitle, published as the artist, and artwork:

- For a document opened from the library, the subtitle is the folder's name.
- For a note the panel wrote, the subtitle is `From clipboard`.
- Artwork is one image rendered once at launch, the waveform glyph on the accent colour, so the card has a plate rather than a grey square.

`NowPlayingCenter.set(info:)` takes the two new keys, `subtitle` and `artwork`, and `SystemNowPlayingCenter` maps them to `MPMediaItemPropertyArtist` and `MPMediaItemPropertyArtwork`.
`NowPlaying.update(title:)` becomes `update(title:subtitle:)`.

## Architecture

### `ClipboardPreview`, in `Vault`

A value: `text`, `title`, `words`, `estimate(factor:)`.
Built from a string by `ClipboardPreview(text:)` with the trim `AppModel.clipboardText` does today, which moves here, returning nil for empty text.
Title is `Title.from`, words and the estimate are `Estimate`'s, so the panel can never disagree with the card the note gets once it is written.
It lives in `Vault` next to `Title` and `NoteName` because it is the note before it is a file; `Vault` already imports `Prose` and still knows nothing about speech.

### `AppModel`

- `clipboardPanel: ClipboardPanelState?` replaces `shakeCount`. The state is an enum: `.empty`, `.preview(ClipboardPreview)`, `.playing(ClipboardPreview)`, `.needsFolder(ClipboardPreview)`.
- `pasteAndPlay()` becomes `previewClipboard()`: reads the clipboard once, builds the preview, and sets the state by the rules above.
- `playPreview()` is what the panel's Play calls: writes the note through the existing `pasteNote(text:andPlay:)`, then moves the state to `.playing`.
- `dismissClipboardPanel()` sets the state to nil.
- The hotkey handler calls `previewClipboard()`.

All of that is on the model so it is tested in `AppModelTests` with the fake vault and fake provider, without a panel on screen.

### `ClipboardPanel`, in `Aloud`

- `ClipboardPanelController` owns one `NSPanel`: `.nonactivatingPanel`, `.borderless`, `.fullSizeContentView`, floating level, `hidesOnDeactivate` false, `collectionBehavior` `[.canJoinAllSpaces, .fullScreenAuxiliary]`, so it shows over a full-screen app too.
- Its content is an `NSHostingView` of `ClipboardPanelView`, which reads the model and draws with `GlassBar` and the existing `TransportButton`, `Scrubber` and `RateButton`.
- The controller observes `model.clipboardPanel`: non-nil orders the panel front and positions it, nil orders it out. Positioning is `NSScreen.screens.first { $0.frame.origin == .zero }`, the screen that carries the menu bar, centred horizontally, top edge at that screen's `visibleFrame.maxY` minus `Space.s`.
- A global event monitor for mouse-down outside the panel and a local monitor for Escape and Enter call the model's dismiss and play, since a non-activating panel is never key and cannot take key equivalents the SwiftUI way.
- Installed from `AppModel.start()`'s caller in `AloudApp`, alongside the menu-bar scene, so it exists with the window closed.

### `AloudUI`

- `Size.clipboardPanelWidth` 360, `Size.clipboardPlate` 88: the panel's width and the glyph plate's side.
- `Motion.emptyPanelHold` 1.6 s: how long the empty-clipboard panel stays.
- `Type.panelTitle`, `Type.panelSubtitle`.
- The gallery gets the panel in each of its four states.
- `LiteralLintTests` covers the new files as it covers the rest.

## Data flow

1. Hotkey. `previewClipboard()` reads `NSPasteboard.general` once and sets `clipboardPanel`.
2. The controller sees the state, positions the panel, orders it front without activating.
3. Play, Enter or Space. `playPreview()` writes the note, refreshes the vault, opens the document, starts the player, and sets `.playing`.
4. The panel's transport reads and drives `model.player` directly, as `MenuBarPanel` does.
5. `NowPlaying` pushes title, subtitle and artwork; the system card shows the same note.
6. Escape, click outside, or the empty hold expiring sets the state to nil and the panel goes.

## Error handling

- Writing the note fails: the panel's subtitle carries the error, as `notice` does in the window, and the transport returns to the before-Play state so Play can be tried again.
- The panel is open when the app quits: nothing to do, the panel is not restorable and the note, if written, is on disk.
- Two displays: the panel goes to the one with the menu bar, never the one under the cursor, so it is in the same place every time.

## Testing

- `ClipboardPreviewTests` in `VaultTests`: trim, empty, title from the first line, word count, estimate at 1x and 2x.
- `AppModelTests`: hotkey with text sets `.preview`; with empty clipboard sets `.empty`; with no folder sets `.needsFolder`; `playPreview` writes exactly one note and sets `.playing`; a second hotkey with different text swaps the preview and does not stop the player; the same text is a no-op; dismiss clears.
- `NowPlayingTests`: the fake centre receives subtitle and artwork.
- The panel's placement and its key handling are AppKit, checked by hand: the hotkey from Safari, from a full-screen app, on an external display, with the window closed.

## Out of scope

- A rate button on the panel. The system card has none, and the transport bar and menu-bar panel both carry one.
- Reading the clipboard's rich text, files or images. Text only, as today.
- Any change to the menu-bar panel or the window's Cmd+Shift+V, which keep writing the note at once, since both are gestures made inside Aloud.
