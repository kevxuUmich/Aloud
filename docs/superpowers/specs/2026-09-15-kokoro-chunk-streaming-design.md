# Kokoro chunk streaming: design

Amends `2026-09-13-kokoro-voices-design.md`, which built the engine that this changes.
Everything there still holds unless a line below says otherwise.

## The problem, measured

Measured on 2026-09-15 on the reader's own note (`Aloud Notes/Home.md`, pasted from a web page, so the header, nav and stat labels have no blank lines between them and become one 714-character sentence), with the reader's settings (`af_sarah`, 1.75x), in the debug build `make dev` produces, on an Apple M2 Pro.
The measurement was `Tests/KokoroTests/ZZMeasureHomeTests.swift`, a temporary test that is not kept.

- Every render the SDK returns opens with 0.32 to 0.39 s of silence and closes with 0.37 to 0.41 s of it.
- The SDK splits any sentence over about 128 phonemes (roughly 120 to 150 characters) into clause chunks, renders each as a standalone utterance, and joins them with a 5 ms crossfade.
  So every seam is a 0.71 to 0.81 s dead stop in the middle of a sentence: sentence 0 of the note has fourteen of them across 34.5 s of audio, and an ordinary 169-character sentence has two.
  This is what the reader hears as "the voice stops every few phrases".
- Between sentences the reader hears the tail and the next lead, about 0.75 s, on top of the 0.2 s "After a sentence" setting, so that setting understates by 0.75 s.
- Rendering itself keeps up: 0.2 to 0.45 of real time in the debug build (about 5x slower than the release numbers recorded in `KokoroEngine.computePolicy`), and the one-sentence render-ahead waited at 2 of 39 boundaries, 0.8 s at worst.
  Loading is heard in one place: the whole sentence is rendered before its first note is played, which for the 714-character sentence is 10.9 s.
- Kokoro reports no word positions, so a speed change (and a switch to an Apple voice) stops, re-renders the whole sentence at the new speed, and speaks it from its first word.
  Inside the 714-character sentence that is 11 s of silence followed by "Home Cases About" again.
  This is what the reader described as going "all the way back to where I initially started it".

### After

The same measurement once the plan below had run, same note, settings, build and machine:

- Every render's lead and tail is 0.030 s, the margin, in place of 0.32 to 0.39 s and 0.37 to 0.41 s.
- Sentence 0 is 15 chunks at 1.75x; the first renders in 1.03 s, and every later chunk renders in less time than the one before it plays, so the queue stays ahead even in the debug build.
- In a separate copy of the app driven through the Playback menu: Play to the first chunk queued on the player node took 1.9 s, of which 0.85 s was the SDK's chunk list (it phonemizes the whole sentence to plan it) and 1.07 s the first render, in place of the 10.9 s render of the whole sentence.
- Two Faster presses and three Slower presses during sentence 0, crossing the 2x cap in both directions, were each answered by a stretch of the sentence in the air (1.14, 1.29, 1.14, 1.0, 0.86) with no render and no restart, and the sentence after it was rendered at the speed the reader had settled on, unstretched.
- The sentences after it followed each other at their natural spacing, with no stall at a boundary.

## What changes

1. **A sentence is rendered and played chunk by chunk.**
   The engine asks the SDK for the chunk list of a sentence (its `prepare` returns one prepared input per chunk, each with its `text`), renders the chunks one at a time in order, and the provider queues each chunk on the player node the moment it is rendered.
   The first note of a sentence is heard after its first chunk renders rather than after all of them.
2. **The silence around each chunk is trimmed.**
   Each render is cut down to its speech with a 30 ms margin on either side.
   Between two chunks of one sentence the provider inserts a fixed beat, `KokoroVoiceProvider.seamPause`, 180 ms, the length of a spoken comma.
   Between two sentences the only silence is the reader's own pause setting, which is now what it says.
3. **A speed change mid-sentence is heard where the reader is.**
   The provider answers `setRate` for any speed while a sentence is in the air: the rest of that sentence is time-stretched on the playback by `new speed / rendered speed`, and the next sentence is rendered at the new speed with no stretch.
   Nothing is stopped and nothing is rewound; the `Player`'s clock keeps the share of the sentence already heard, as it already does for a re-timed sentence.
   The sentence rendered ahead is re-rendered at the new speed straight away, so the boundary is still a hit.
4. **Renders are one ordered chain.**
   The engine is one actor, and the SDK runs a whole chunk without suspending, so the chunks of two sentences must not interleave: each sentence's render is chained after the render before it.
   This replaces the provider's `rendering` counter and its rule that a prefetch starts only at zero.

Unchanged: the `VoiceProvider` protocol and `Player`; `onWord` is still never called for a Kokoro voice, so the reader sees the sentence highlighted and never a chunk.
A switch from a Kokoro voice to an Apple voice still speaks the current sentence again from its start (the app model's `respeakCurrentSentence`), now with no render wait in front of it; resuming from the current chunk is a follow-up, not this change.

## Architecture

`Sources/Kokoro`:

- `Silence.swift`: `Silence.trim(_:threshold:margin:)`, a pure function over `[Float]`, with its threshold (0.002) and margin (720 samples, 30 ms at 24 kHz).
- `KokoroEngine.swift`: `KokoroSynthesizing` gains `chunks(of:voice:speed:) async throws -> [String]`; `synthesize` returns trimmed samples.
- `KokoroPlayback.swift`: `KokoroPlaying.play` becomes `enqueue(_:completion:)`, which queues a buffer behind whatever is queued and calls back when that buffer has been heard; `setVolume`, `setRate`, `stop` and `shutdown` stay.
  Volume and stretch are set on the node by the provider before a sentence's first buffer.
- `SentenceRender.swift`: one sentence's render, `@MainActor`: the chunk list as a task, then one task per chunk, each queued behind the one before it and the whole chained after the previous sentence's render; `samples(ofChunk:)` waits for one, `renderAll()` queues them all, `cancel()` cancels every task.
- `KokoroVoiceProvider.swift`: `speak` walks the chunks of the sentence's render, enqueues each as it lands with the seam beat after every one but the last, and reports finished (after the pause) once every queued buffer has been heard; `prepare` builds the next sentence's render chained after the current one; `setRate` stretches; `stop` cancels both renders.

## Data flow

```
Player.speakCurrent
  provider.speak(sentence N)          -> render N (hit on prepared, else new, chained after the last render)
                                          renderAll(): plan, then chunk 0, 1, ... in order
                                          for each chunk: await samples -> enqueue(samples + seam)
                                          all queued and all heard -> pause -> onFinish
  provider.prepare(sentence N+1)      -> render N+1, chained after render N, renderAll()
Player.rate = new (while playing)
  provider.setRate(new) -> true       -> playback.setRate(new / rendered speed of N)
                                         render N+1 keyed at the old engine speed is cancelled and rebuilt at the new one
```

## Testing

- `Silence.trim`: leading and trailing silence removed, margin kept, margin clamped at the ends, all-silent input comes back empty.
- `SentenceRender`: chunks render in order and one at a time; a render chained after another waits for all of that one's chunks; `samples(ofChunk:)` on a failed plan is nil; `cancel` stops the queue.
- `KokoroVoiceProvider`: the first chunk is queued before the second renders; the seam beat follows every chunk but the last; the sentence finishes only after the last queued buffer is heard; a chunk that fails is skipped; `setRate` mid-sentence stretches and rebuilds the prepared render; a prepare during the current sentence renders after it; stop cancels both.
- `KokoroIntegrationTests` (gated on the real bundle): a long sentence has more than one chunk, each chunk renders as one piece, and every render's lead and tail are within the margin.
- The temporary measurement is re-run once by hand on `Home.md` and its numbers go into the plan's final task, then the file is deleted.

## Out of scope

- Resuming an Apple voice from the current chunk after a Kokoro-to-Apple switch.
- Highlighting the chunk being spoken.
- Whether `make dev` should build with optimisation; noted for the reader, decided separately.
