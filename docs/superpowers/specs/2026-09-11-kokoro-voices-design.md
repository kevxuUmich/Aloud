# Kokoro voices - design

Aloud speaks with the system voices today, through `AVSpeechSynthesizer`.
This adds a second engine, Kokoro, run on the Mac through sherpa-onnx, so a reader can pick a neural voice that Apple does not ship.
It is written ahead of the work, from a throwaway prototype's findings, so the shape is settled before the first line lands.
It is not scheduled: the recommended Apple voices in the picker are the first answer to "the default voice sounds flat", and Kokoro is the second, to be built when readers ask for it.

## What the prototype found

The prototype loaded Kokoro through sherpa-onnx on Apple Silicon and timed it.

| Build | Size | Real-time factor |
| --- | --- | --- |
| fp32, CPU | 310 MB | 0.27 |
| int8, CPU | 114 MB | about 0.75 |
| fp32, CoreML | 310 MB | slightly worse than CPU |

A real-time factor of 0.27 means a sentence renders in about a quarter of the time it takes to say.
The next sentence can be rendered while the current one plays and playback never catches up with rendering.
The cost is about half a second of silence after Play, before the first sentence is ready, plus a one-time model load when the engine starts.

Two findings go against instinct and the design follows them.
The small quantized model is nearly three times slower than the full one on this hardware, so the full fp32 model ships, not the small file.
CoreML buys nothing, so the engine runs on the plain CPU provider.

The model set is 103 voices, 28 of them English.

The engine exposes no per-word timings.
It returns audio for a whole string, with no map from time back into the text.

sherpa-onnx will not start Kokoro without espeak-ng's data directory present.
espeak-ng is licensed GPL-3.

The model, the voices file and the espeak-ng data come to about 400 MB, which cannot ship inside the app bundle.

## The decision that is not technical

espeak-ng under GPL-3 inside a distributed app carries obligations that reach the app.
This spec does not settle that, because it is not a question the code can answer.
The three ways through, in the order they should be looked at:

1. Fork sherpa-onnx and cut the espeak-ng dependency for Kokoro, so the lexicon-only path runs. Kokoro's English needs a grapheme-to-phoneme step, and the fork has to supply one under a compatible licence, or fall back to the lexicon alone and accept worse pronunciation of words outside it.
2. Accept the GPL footprint, with a real licensing opinion on what that means for Aloud's own licence and distribution.
3. Choose another engine whose dependencies are clean, and keep the architecture below, which does not depend on Kokoro in particular.

Nothing below is built until one of these is chosen.
Everything below is written so that the choice changes only the `KokoroEngine` layer and the download manifest.

## What the listener sees

- The voice picker gains a second group of sections, after the Apple ones, headed by the engine's name. Each voice is a `VoiceRow` like any other, previewable and pickable, and the picked voice is remembered in `Defaults.voiceID` like any other.
- Before the engine's files are downloaded, the picker shows one row in that group, `Neural voices`, with the download arrow in place of the preview button and the caption `Download, 400 MB`. Picking it opens Settings to the Voices section.
- Settings gains a Voices section with one control: a `Download` button that becomes a progress bar, then the words `Installed, 400 MB` with a `Remove` button beside them. Downloading happens in the background and survives the window being closed. A failed download reports the error in the section and keeps the button.
- Play with a Kokoro voice picked: the first sentence begins after about half a second, and playback is otherwise what it is today. The sentence highlight follows the sentence being spoken.
- The word highlight with a Kokoro voice is estimated, not reported. It moves through the sentence at a pace set by character count against the sentence's rendered length. It will drift within a long sentence and snap true at the next one. This is written down here so nobody later files it as a bug.
- Rate and volume work. Rate is applied at synthesis, since Kokoro takes a speed parameter, so the rendered audio is at the right pace and a rate change takes at the next sentence. Volume is the player node's gain and takes at once.
- Pauses after a sentence are silence appended to the rendered audio, so the same `Pauses` settings apply.
- If the engine's files go missing after a voice was picked, the player falls back to the system voice with the same notice the app already shows for a removed Apple voice.

## Architecture

### `Speech`

`VoiceProvider` stays the one protocol the player speaks through.
Three things are added beside it.

`KokoroVoiceProvider: VoiceProvider`.
It owns the engine and an `AVAudioEngine` with one `AVAudioPlayerNode`.
`voices` lists the model's voices as `Voice` values whose `id` is prefixed `kokoro.` so they never collide with an Apple identifier, with `language` from the voice's tag and `quality` `.premium`.
`speak` renders the text on a background task, appends the pause as silence, schedules the buffer, and calls `onFinish` when the buffer completes.
It calls `onWord` on a timer from the estimated timings described under `WordTiming` below.
`stop` stops the node and cancels the render in flight.
`preview` renders the preview sentence and plays it, interrupting whatever is playing, as the Apple provider does.
`refreshVoices` is a no-op: the set is the model's and does not change under the app.

`CompositeVoiceProvider: VoiceProvider`.
Holds the Apple provider and the Kokoro provider, concatenates their `voices`, and routes every call by the picked voice's identifier prefix.
`defaultVoice` is the Apple provider's.
`stop` stops both, since a preview from one may interrupt speech from the other.
This is what `AppModel` is built with once Kokoro exists; nothing in `Player` or `AppModel` learns which engine it is talking to.

`WordTiming`.
A pure function from a sentence and its rendered duration to a list of `(NSRange, TimeInterval)` pairs, one per word, at offsets proportional to the word's share of the sentence's characters, with punctuation weighted as a fraction of a character.
Tested on its own.
It is the whole word-highlight story for an engine that reports none, and swapping in real timings later means replacing the call, not the player.

### `KokoroEngine`

A thin wrapper over sherpa-onnx's C API, in its own module so the licence question is confined to one directory.
`init(modelDirectory:)` loads the model once.
`render(text:voice:speed:) async throws -> AVAudioPCMBuffer`.
`voices: [(id: Int, name: String, language: String)]`.
The module is built only when the model files are present at build time on the developer's machine and is otherwise a stub that reports `unavailable`, so the app builds in a checkout that has not downloaded anything.

### `Vault`

`ModelStore`.
Where the files live: `Application Support/Aloud/Models/kokoro/`.
`state: .absent | .downloading(progress) | .installed(bytes) | .failed(error)`.
`download()` runs a `URLSession` background download of one archive from a URL and expected checksum written in a manifest in the app, verifies the checksum, unpacks, and moves into place atomically.
`remove()` deletes the directory.
The store is a `@Observable` the Settings section reads.

### `Aloud`

- `AppModel` is built with the composite provider when the store is `.installed`, and with the Apple provider alone otherwise. A download finishing while the app runs rebuilds the composite provider in place; the player's current voice is unaffected because Apple identifiers do not move.
- The voice popover's `load()` appends the Kokoro group, or the one download row, from what the provider reports.
- `SettingsView` gains the Voices section bound to the store.
- Every size, spacing and string that the section introduces goes through `Tokens.swift`, as `LiteralLintTests` requires.

## Data flow

1. Play with a Kokoro voice picked. `Player` calls `provider.speak` with the sentence, as it does today.
2. The composite provider routes to `KokoroVoiceProvider`.
3. The provider renders the sentence, appends the pause, schedules it on the player node, and starts the word timer from `WordTiming`.
4. When the node reports the buffer done, `onFinish` runs and `Player` advances.
5. While the sentence plays, `Player` already asks for the next sentence only after `onFinish`. To hide the render time, the provider renders the sentence after the one it was handed as soon as the current buffer is scheduled, keyed by the text, and serves it from that cache when asked. A cache miss is a normal render. The cache holds one entry.
6. Stop or seek. `Player` calls `stop`; the provider stops the node, cancels the render task and drops the cache.

## Error handling

- Model files missing at launch with a Kokoro voice remembered: `defaultVoice` is used and the existing unavailable-voice notice names the voice.
- Render fails mid-document: the provider calls `onFinish` after posting the error to a `lastError` the model surfaces as a notice, so playback moves on rather than stalling.
- Download fails: the section shows the error and the button; nothing partial is left in the models directory.
- Disk full during unpack: treated as a failed download; the partial directory is removed.
- The app quits during a download: `URLSession` background downloads continue and the store reconciles on the next launch.

## Testing

- `WordTimingTests`: one word, many words, punctuation, an empty sentence, monotonic offsets that end at the duration.
- `CompositeVoiceProviderTests` with two fake providers: routing by prefix, `stop` reaching both, `voices` concatenated in order.
- `ModelStoreTests` with a local file URL and a fake session: checksum mismatch rejects, partial unpack leaves nothing, remove clears.
- `KokoroVoiceProvider` against the real engine is tested by hand, since it needs the files: first-sentence latency, a rate change taking at the next sentence, volume, a preview interrupting speech, stop mid-sentence.
- `AppModelTests`: a download finishing swaps the provider without changing the picked voice.

## Out of scope

- Real word timings. They wait on an engine that reports them.
- Streaming synthesis within a sentence. The sentence is the unit; at 0.27 real-time the half-second is at the first sentence only.
- Voice cloning, voice mixing, or any Kokoro feature past picking one of its shipped voices.
- Shipping the model in the bundle. It is a download.
- Any change to how Apple voices are listed, previewed or picked.
