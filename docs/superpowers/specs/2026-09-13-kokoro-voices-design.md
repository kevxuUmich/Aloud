# Kokoro voices - design

Aloud speaks with the system voices today, through `AVSpeechSynthesizer`.
This adds a second engine, Kokoro, run on the Mac's Neural Engine through CoreML, so a reader can pick a neural voice that Apple does not ship.
Seven English voices ship in this pass: Bella, Sarah, Michael and Fenrir in American English, and Emma, George and Fable in British English.

This supersedes the spec of 2026-09-11, which was written around sherpa-onnx.
That spec found two things that still stand.
espeak-ng, which sherpa-onnx needs for English, is licensed GPL-3, and that licence reaches an app that ships it.
The route below has no espeak-ng in it: the phonemizer is Misaki, under Apache 2.0, and the runtime is CoreML.
It also found that the ONNX int8 model was slower than fp32 on this hardware, which is moot here because CoreML runs fp16 on the Neural Engine.
Everything else in the old spec is replaced by this one.

## Decisions taken

These were settled in conversation and are not open.

- The model is downloaded on first use, not bundled. The app stays about 6 MB.
- The download is one archive attached to a GitHub release on the Aloud repo, pinned in code by URL, version and SHA-256. Nothing is fetched from Hugging Face at runtime.
- The engine is the kokoro-coreml project's Swift SDK, `KokoroTTS`, running four CoreML models on the Neural Engine. The alternatives, sherpa-onnx on the CPU and mlx-audio-swift on the GPU, were weighed and set aside for licence, size and dependency reasons.
- Kokoro voices highlight the sentence being read, not the word. The engine reports no word timings and the product is built for listening, so the sentence is enough.
- English only in this pass. Mandarin voices need a phonemizer the SDK does not have, and they are a follow-up.
- The SDK's phonemizer, MisakiSwift, depends on MLX for a 3 MB fallback network that pronounces words missing from its dictionaries. MLX's shaders cannot be built by `swift build`. Aloud uses a fork of MisakiSwift in which that network is reimplemented on Accelerate, so MLX leaves the dependency tree.

## What the SDK gives and requires

Checked against the SDK's source, not its README.

- `KokoroTTS.load(resources: .directory(url, compiledModelsDirectory: url))` loads from any folder that holds its runtime manifest. No network is involved.
- The manifest must declare exactly one duration model of 128 tokens, one bucket of 15 seconds with its three packages, every voice file with its digest, and a provenance flag set to true. The SDK verifies every digest at load and every model package at first use.
- Any of the 28 English voices is accepted when its file is declared. The other prefixes are refused by the SDK.
- `synthesize(text, voice:, options:)` is an actor method returning 24 kHz float samples. Speed is a positive multiplier with no clamp. Cancellation is honoured between chunks.
- Text longer than about 120 characters is chunked inside the SDK and the audio stitched, so the player hands over whole sentences.
- First use compiles the four models with CoreML and caches the result in a folder the caller names. Later loads take about a second.
- `KokoroError` is not `Sendable`, so the provider wraps it.
- The SDK's own downloader resolves nested paths relative to a manifest URL, which GitHub release assets cannot serve. Aloud does not use it.

## What the listener sees

- The voice picker gains a section at the top, above Recommended, headed `Kokoro`, with a one-line caption: seven voices, one download of about 165 MB, runs on your Mac.
- The seven voices are listed in that section grouped by region, each in the same `VoiceRow` as an Apple voice, with the same preview button, badge and checkmark.
- Before the download, every row shows the download arrow and the size badge, as the uninstalled recommended voices do. Clicking any row starts the one download.
- During the download, the section header shows a progress bar with a Cancel button and the rows are dimmed.
- When the download finishes, the rows become playable and the row that was clicked is picked, so the reader's intent completes without a second click.
- On the first pick after an install, the picked row shows a spinner in place of the play icon while the models compile and load, a few seconds once.
- If the download or install fails, the header shows the error in one sentence with a Retry button.
- Search finds Kokoro voices like any other.
- Settings gains a row under the Voice picker: the installed version and size with a Remove button, or a Download button when absent.
- Play with a Kokoro voice picked: the first sentence begins within about half a second, and playback is otherwise what it is today, with the sentence highlight following the sentence being spoken.
- Rate, volume and pauses work.
  A volume change applies to the sentence being played at once, with no new audio.
  Above 2x the model's speed is capped at 2 with an `AVAudioUnitTimePitch` covering the rest, so a change among the speeds at or above 2x applies to the sentence being played at once as well.
  A rate change that needs audio the engine has not rendered re-speaks that sentence from its start rather than from the current word, since there is no current word.
- If the model is removed while a Kokoro voice is picked, the player falls back to the system voice with the notice the app already shows for a removed Apple voice.
- The README gains one sentence under the voices bullet and one under the line that says Aloud sends nothing off your Mac: Kokoro voices are a one-time download from Aloud's own releases and run entirely on the Mac afterwards.

## Architecture

### Packages

Three forks, each pinned by exact revision from `Package.swift` and `project.yml`.

`MisakiSwift`, forked under the app author's GitHub account.
The one change is the `FallbackNetwork` folder: the MLX implementation of the small BART network becomes an Accelerate one reading the same weight and config files.
The network is one encoder layer, one decoder layer, one attention head, a model width of 128, a feed-forward width of 1024 and a vocabulary of 63 symbols, with greedy decoding to at most 64 positions.
The package's dependencies drop to none.
The Apache 2.0 licence file stays.

`KokoroTTS` and `KokoroPipeline`, forked together from kokoro-coreml.
The SDK's manifest pins MisakiSwift by revision to the upstream author's repo, so the fork repoints that one line at the Misaki fork and changes nothing else.
Forking rather than vendoring keeps upstream fixes a rebase away.

### `Kokoro`, a new module in Aloud

Beside `Speech`, depending on `Speech` for the protocol and on the SDK.
`Speech` stays free of the SDK, so its tests stay fast and the app still runs with `--silent`.

`KokoroCatalogue`.
The seven voices as static data: the Aloud voice id, the Kokoro voice id, the display name, the language tag and the region.
Aloud ids are the Kokoro id under a `kokoro.` prefix, so `kokoro.af_bella`, and never collide with an Apple identifier.
Quality is `.premium`, so the voices sort to the top of their sections.

`KokoroRelease`.
The pinned download: the release URL, the bundle version string and the archive's SHA-256, in one file.
Bumping the bundle is a change to these three values and a new release asset.

`KokoroStore`.
A main-actor `@Observable` owning the model's life on disk.
State is `.absent`, `.downloading(fraction)`, `.installing`, `.installed(version, bytes)` or `.failed(message)`.
`download()` starts a background `URLSession` download task, so it survives the window closing and reports progress.
It resumes from resume data if the app quit mid-download.
On completion the file's SHA-256 is checked against `KokoroRelease` before anything is extracted, and a mismatch deletes the file and fails.
The archive is extracted with the AppleArchive framework into a temporary folder, moved into place, and a completion marker written last.
`cancel()` cancels the task and returns to `.absent`.
`remove()` deletes the version folder and the compiled cache.
On launch, a version folder without the marker is removed, and once the pinned version is installed any older version folder is removed.

`KokoroEngine`.
An actor wrapping the SDK: `load()` creates the `KokoroTTS` and runs its prewarm, `synthesize(text, voice, speed) -> [Float]`, and `unload()`.
It maps `KokoroError` into a `Sendable` error of its own.

`KokoroPlayback`.
An `AVAudioEngine` with one `AVAudioPlayerNode` at 24 kHz mono, with `play(samples, volume, completion)` and `stop()`.
It restarts the engine on the audio configuration-change notification so an unplugged headphone set does not leave it silent.

`KokoroVoiceProvider: VoiceProvider`.
`voices` is the catalogue when the store is `.installed`, and empty otherwise.
An empty list is what makes the picker show download rows and what makes a saved Kokoro voice fall back cleanly through the player's existing check.
`speak` asks the engine for the sentence at the rate's factor as speed, plays the samples at the given volume, waits the pause on a timer after the buffer ends, then calls `onFinish` on the main actor.
`onWord` is never called.
`stop` cancels the synthesis in flight, stops playback and bumps a generation counter, so a late completion from a cancelled sentence is ignored, the guard the Apple provider uses.
`prepare` synthesizes the next sentence in the background into a one-slot cache keyed by text, voice and rate, and `speak` serves a hit from it, so sentence boundaries carry no synthesis gap.
`preview` synthesizes the preview sentence in the chosen voice and plays it through the same engine, waiting for the model if it is still loading.
`warm()` loads the engine off the main actor, reporting a `isWarming` flag the picker draws as a spinner.
It is called when a Kokoro voice is picked and at launch when the saved voice is one.
Picking an Apple voice unloads the engine to give the memory back.
`refreshVoices` is a no-op.

### `Speech`

`VoiceProvider` gains `prepare(_ text: String, voice: Voice?, rate: Rate)` with a default no-op in an extension.
The Apple and fake providers inherit the no-op.
`Player.speakCurrent` calls `prepare` for the sentence after the current one when there is one.

`CompositeVoiceProvider: VoiceProvider`.
Holds the Apple provider and the Kokoro provider, concatenates their `voices` with Kokoro's first, and routes `speak`, `prepare` and `preview` by the voice id's prefix.
`defaultVoice` is the Apple provider's.
`stop` stops both, since a preview from one may interrupt speech from the other.
`refreshVoices` refreshes both.

### `Aloud`

- `AloudApp` builds the composite provider from an `AppleVoiceProvider` and a `KokoroVoiceProvider` over one `KokoroStore`, and hands the store to the model.
- `AppModel.pickVoice` warms the Kokoro provider when the picked voice is a Kokoro one, and unloads it otherwise.
- `VoicePopover` draws the Kokoro section from the catalogue and the store's state, above the recommended section, and hides it while the search field has text unless a Kokoro voice matches.
- `SettingsView` gains the Kokoro row bound to the store.
- Every size, spacing and string the section introduces goes through `Tokens.swift`, as `LiteralLintTests` requires.
- The client network entitlement is added to `App/Aloud.entitlements` and to the entitlements block in `project.yml`, which states the sandbox keys twice on purpose.

## The model bundle and the packaging tool

A Swift script in `Tools/`, run as `make kokoro-bundle`, builds the archive attached to a release.

- Inputs: the four CoreML packages from the kokoro-coreml Hugging Face repo, the seven voice files, and the vocabulary and harmonic weight assets the SDK expects. The script downloads them into `.build` against pinned checksums, so a rebuild on another machine produces a byte-identical bundle.
- Layout: a `coreml` folder with the four packages, a `voices` folder with seven files, a `runtime` folder with the two assets, and the SDK's `KokoroRuntimeManifest.json` at the root.
- The script computes every per-file digest and per-package tree digest with the SDK's own rules, taken from its `build_sdk_bundle.mjs`, and sets the provenance flag. The bundle profile is named `aloud`.
- Output: one Apple Archive, `kokoro-<version>.aar`, compressed, about 165 MB, and a sidecar text file with its SHA-256.
- The archive is attached to a release tagged `kokoro-models` on the Aloud repo, so the model does not churn with app releases.
- The four models are the SDK's minimum set, so there is nothing to trim.

## Where files live

- Models: `Application Support/Kokoro/<version>/` inside the sandbox container.
- Compiled CoreML cache: `Caches/Kokoro/<version>/`, excluded from backup.
- Both are the app's own directories, so no file entitlements change.

## Data flow

1. Play with a Kokoro voice picked. `Player` calls `provider.speak` with the sentence, as it does today, and `provider.prepare` with the next one.
2. The composite provider routes both to `KokoroVoiceProvider`.
3. The provider serves the sentence from its cache or synthesizes it, plays the samples, and starts synthesizing the next sentence.
4. When the buffer ends and the pause elapses, `onFinish` runs and `Player` advances.
5. Stop or seek: `Player` calls `stop`; the provider cancels the synthesis in flight, stops playback, drops the cache and bumps the generation.

## Error handling

- Download or install failures land in the store's `.failed` with a plain message: no connection, the file did not match, or not enough disk space. The popover header and the Settings row show it with Retry. Nothing is retried silently.
- A model load failure puts the provider back to unloaded and routes through the player's unavailable-voice path, so the reader hears the system voice and sees why.
- A synthesis failure on one sentence, such as text that phonemizes to nothing, finishes that sentence silently and advances, so a stray symbol never stalls a reading. The provider logs it.
- Unknown words go through the Accelerate fallback rather than being dropped. The fork keeps Misaki's dropped-word counter so a test can assert it stays at zero on a fixture.
- A crash mid-install leaves a folder without the marker, which the next launch removes.
- The app quitting mid-download leaves resume data, which the next launch resumes from.

## Testing

- `KokoroTests`: the catalogue and id prefixing. The store against a temporary directory and a stubbed URL session: resume, checksum mismatch, the completion marker, crash-mid-install cleanup, cancel and removal. The provider against a fake engine and fake playback: stop, generation guarding, the pause timer, prefetch cache hits and misses, preview, and warm and unload.
- `SpeechTests`: `CompositeVoiceProvider` with two fakes, covering routing by prefix, `stop` reaching both, and `voices` in order. `Player` calls `prepare` for the next sentence and not after the last.
- The Misaki fork: the Accelerate network against the MLX one on a fixed word list, run once to produce a golden file that is checked in, then the golden file is the test.
- The packaging tool: a test that builds a bundle from local fixture files and loads it through the SDK, so a manifest the SDK would refuse fails in CI rather than on a reader's Mac.
- One gated integration test synthesizes a sentence with the real model when the bundle is present on the machine, and is skipped otherwise.
- By ear: each of the seven voices at 1x, 2x and 3x, the sentence gap with prefetch on, a preview interrupting speech, stop mid-sentence, and an unplugged headphone set.

## Checks during implementation

- Speed above 2x is not passed straight to the model.
  The model saturates near 2.3x, so the provider caps the model's speed at 2 and covers the rest with an `AVAudioUnitTimePitch` on the playback engine.
- The kokoro-coreml SDK is young. The forks pin exact revisions, and nothing is vendored until a pin has to be worked around.

## Out of scope

- Word timings. The engine reports none, and the product does not need them.
- Mandarin voices. They need a Chinese phonemizer the SDK lacks, and they are a follow-up.
- Streaming synthesis within a sentence. The sentence is the unit.
- Voice mixing or any Kokoro feature past picking one of its shipped voices.
- Shipping the model in the app bundle.
- Any change to how Apple voices are listed, previewed or picked.
