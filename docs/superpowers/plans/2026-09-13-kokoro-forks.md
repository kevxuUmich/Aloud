# Kokoro forks implementation plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Two forks that build with a plain `swift build`: MisakiSwift with its MLX fallback network rewritten on Accelerate, and the kokoro-coreml SDK repointed at that fork.

**Architecture:** MisakiSwift's English phonemizer resolves words from two dictionaries and hands the rest to a tiny BART network, which upstream runs on MLX.
This plan moves the token type MisakiSwift borrows from an MLX utilities package into MisakiSwift itself, replaces the MLX network with a pure Swift one on Accelerate that reads the same weight files, and proves it against the original PyTorch model with a checked-in golden file.
The SDK fork changes one dependency line and un-skips two tests that the MLX dependency had forced off.

**Tech Stack:** Swift 6.2 packages, Accelerate (cblas and vDSP), swift-testing, the `gh` CLI, `uv` with PyTorch and Transformers for the one-time golden generation.

**Spec:** `docs/superpowers/specs/2026-09-13-kokoro-voices-design.md`, sections "Decisions taken" and "Architecture, Packages".

This is plan 1 of 3.
Plan 2 builds the model bundle and plan 3 integrates the app.
Both depend on the two fork revisions this plan produces.

## Global Constraints

- Both forks live under the GitHub account `kevinxu-cmd` and are pinned by exact revision from Aloud.
- After this plan, neither fork depends on MLX, MLXNN, MLXUtilsLibrary, swift-numerics or ZIPFoundation.
- `swift build` and `swift test` must pass in both forks from the command line, with no xcodebuild.
- Platform minimums stay as upstream has them: macOS 15 and iOS 18.
- The Apache 2.0 `LICENSE` file stays in each fork, unchanged.
- MisakiSwift's public API is unchanged except that `MToken` and `Underscore` are now declared in MisakiSwift itself.
- The Accelerate network must reproduce the PyTorch model's greedy output exactly on the golden word list, for both dialects.
- Upstream's own tests in both forks keep passing.
- The user's global rule: never use the em dash character in any file.

## Facts checked before writing this plan

- The SDK pins MisakiSwift at revision `3a27756a780fc138e328a96e533fb440a3419d5b`, which is also the head of `mattmireles/MisakiSwift`.
- MisakiSwift imports `MLXUtilsLibrary` in three files, and uses only two things from it: the `MToken` and `Underscore` classes.
- MLX is used only in the folder `Sources/MisakiSwift/English/FallbackNetwork/` plus one file `Sources/MisakiSwift/Extensions/MLXArray+DebugPrint.swift`.
- `swift build` of upstream MisakiSwift compiles in about 45 seconds, but any test that touches the fallback network dies with `MLX error: Failed to load the default metallib`.
- Forcing MLX onto the CPU does not help, and this machine's Xcode 26.6 lacks the Metal toolchain component, so xcodebuild fails too.
- The weights are safetensors files, 50 tensors each, all `F32`, listed in Task 4.
- The network is one encoder layer, one decoder layer, one attention head, model width 128, feed-forward width 1024, vocabulary 63, position table 66 rows with BART's offset of 2.
- The PyTorch reference generator in Task 2 runs in about 3 seconds after its first dependency download and produces, for example, `blorptastic` as `blˌɔɹptˈæstɪk` in the US model.

## File structure

MisakiSwift fork, `kevinxu-cmd/MisakiSwift`, branch `main`:

- Create `Sources/MisakiSwift/DataStructures/MToken.swift`: the `MToken` and `Underscore` classes, moved verbatim from MLXUtilsLibrary.
- Create `Sources/MisakiSwift/English/FallbackNetwork/Safetensors.swift`: reads a safetensors file into named float tensors.
- Create `Sources/MisakiSwift/English/FallbackNetwork/Matrix.swift`: a row-major float matrix with the handful of Accelerate operations the network needs.
- Create `Sources/MisakiSwift/English/FallbackNetwork/BARTNetwork.swift`: the encoder, decoder and greedy generation on `Matrix`.
- Modify `Sources/MisakiSwift/English/FallbackNetwork/EnglishFallbackNetwork.swift`: load through `Safetensors` and run `BARTNetwork`.
- Keep `Sources/MisakiSwift/English/FallbackNetwork/BARTConfig.swift` as it is.
- Delete `BARTModel.swift`, `BARTEncoderLayer.swift`, `BARTDecoderLayer.swift`, `BARTLayerNorm.swift`, `MultiHeadAttention.swift`, `FeedForward.swift` in that folder, and `Sources/MisakiSwift/Extensions/MLXArray+DebugPrint.swift`.
- Modify `Sources/MisakiSwift/English/EnglishG2P.swift` and `Sources/MisakiSwift/English/Lexicon/Lexicon.swift`: drop the `import MLXUtilsLibrary` line.
- Modify `Package.swift`: no dependencies, static library, test fixtures resource.
- Delete `Package.resolved`.
- Create `Tools/fallback-words.txt` and `Tools/reference.py`: the golden word list and its generator.
- Create `Tests/MisakiSwiftTests/Fixtures/fallback-golden.json`: the generated golden file.
- Create `Tests/MisakiSwiftTests/SafetensorsTests.swift` and `Tests/MisakiSwiftTests/FallbackNetworkTests.swift`.

kokoro-coreml fork, `kevinxu-cmd/kokoro-coreml`, branch `aloud`:

- Modify `swift-tts/Package.swift`: the MisakiSwift dependency line.
- Regenerate `swift-tts/Package.resolved`.
- Modify `swift-tts/Tests/KokoroTTSTests/KokoroMisakiPhonemizerTests.swift`: remove the runtime skip.

Working directory for the whole plan: `/Users/kevindazoo/aloud/kokoro/`, which is an empty folder in the Aloud checkout that git does not track.
Clone both forks inside it.
Nothing in this plan touches the Aloud package itself.

---

### Task 1: Fork MisakiSwift and clone it

**Files:**
- Create: `/Users/kevindazoo/aloud/kokoro/MisakiSwift/` (a clone)

**Interfaces:**
- Produces: the fork `https://github.com/kevinxu-cmd/MisakiSwift` at upstream revision `3a27756a780fc138e328a96e533fb440a3419d5b`.

- [ ] **Step 1: Fork and clone**

```bash
cd /Users/kevindazoo/aloud/kokoro
gh repo fork mattmireles/MisakiSwift --clone=false --default-branch-only
git clone https://github.com/kevinxu-cmd/MisakiSwift.git
cd MisakiSwift
git rev-parse HEAD
```

Expected: the last line prints `3a27756a780fc138e328a96e533fb440a3419d5b`.
If it prints something else, run `git reset --hard 3a27756a780fc138e328a96e533fb440a3419d5b` so the fork starts from the revision the SDK was tested against.

- [ ] **Step 2: Confirm the upstream build works before changing anything**

```bash
cd /Users/kevindazoo/aloud/kokoro/MisakiSwift
swift build 2>&1 | tail -3
```

Expected: `Build complete!` after roughly a minute.
This proves the toolchain is fine and that later failures are the plan's, not the machine's.

- [ ] **Step 3: Check that the two upstream string tests pass today**

```bash
swift test 2>&1 | grep -E "passed|failed|MLX error" | tail -5
```

Expected: the tests pass, or fail only with `MLX error: Failed to load the default metallib`.
Write down which it was.
If they pass today, they must pass after Task 7.
If they fail with the MLX error today, they must pass after Task 7, which is the point of the work.

---

### Task 2: Generate the golden file from the PyTorch model

**Files:**
- Create: `Tools/fallback-words.txt`
- Create: `Tools/reference.py`
- Create: `Tests/MisakiSwiftTests/Fixtures/fallback-golden.json`

**Interfaces:**
- Produces: `fallback-golden.json` with the shape `{"us": {word: phonemes}, "gb": {word: phonemes}}`, consumed by Task 6's test.

The network only ever sees words the dictionaries did not know, so the list is invented words and unusual names.
Invented words are certainly absent from the dictionaries, and they exercise the full grapheme set including the apostrophe, the hyphen, the period and a character outside the set.

- [ ] **Step 1: Write the word list**

Create `Tools/fallback-words.txt`:

```text
blorptastic
grimbleworth
Dazoo
Kevlarin
o'brienwick
quellingbrook
zantrofy
Mirabexa
thrandalore
vexomirth
Kokoro
Fenrir
Xiaoxiao
Yunxi
snorfleberg
wugs
plimbic
Tarquenth
hyper-loomish
St.Clairborne
McQuistrel
jzxq
Ængstrom
LLVM
gh
a
Bellatrixon
Sarahmund
Michaelovitch
Emmaline-Rose
Georgetta
Fablewright
```

- [ ] **Step 2: Write the reference generator**

Create `Tools/reference.py`:

```python
"""Golden phonemes for the fallback network, from the PyTorch weights it was trained as.

Run from the package root:
    uv run --python 3.12 --with torch==2.8.0 --with transformers==4.51.2 --with safetensors \
        Tools/reference.py

Reads Tools/fallback-words.txt and writes Tests/MisakiSwiftTests/Fixtures/fallback-golden.json.
The decoding loop mirrors the Swift network exactly: greedy, start from BOS, stop at EOS,
at most 49 generated tokens, and phoneme ids above 3 map into phoneme_chars.
"""
import json
from pathlib import Path

import torch
from safetensors.torch import load_file
from transformers import BartConfig, BartForConditionalGeneration

ROOT = Path(__file__).resolve().parent.parent
RESOURCES = ROOT / "Resources"
WORDS = ROOT / "Tools" / "fallback-words.txt"
OUT = ROOT / "Tests" / "MisakiSwiftTests" / "Fixtures" / "fallback-golden.json"


def build(prefix):
    cfg = BartConfig.from_json_file(str(RESOURCES / f"{prefix}_bart_config.json"))
    model = BartForConditionalGeneration(cfg)
    missing, unexpected = model.load_state_dict(
        load_file(str(RESOURCES / f"{prefix}_bart.safetensors")), strict=False
    )
    assert not unexpected, unexpected
    tied = {"lm_head.weight", "model.encoder.embed_tokens.weight", "model.decoder.embed_tokens.weight"}
    assert set(missing) <= tied, missing
    model.tie_weights()
    shared = model.model.shared.weight
    for emb in (model.model.encoder.embed_tokens, model.model.decoder.embed_tokens, model.lm_head):
        assert emb.weight.data_ptr() == shared.data_ptr(), "weights are not tied"
    model.eval()
    raw = json.loads((RESOURCES / f"{prefix}_bart_config.json").read_text())
    return model, raw["grapheme_chars"], raw["phoneme_chars"], cfg


def phonemize(model, graphemes, phonemes, cfg, word):
    g2t = {c: i for i, c in enumerate(graphemes)}
    ids = [cfg.bos_token_id] + [g2t.get(c, 3) for c in word] + [cfg.eos_token_id]
    with torch.no_grad():
        enc = model.get_encoder()(input_ids=torch.tensor([ids]))
        dec = [cfg.bos_token_id]
        for i in range(50):
            if i == 49:
                break
            logits = model(encoder_outputs=enc, decoder_input_ids=torch.tensor([dec])).logits[0, -1]
            nxt = int(torch.argmax(logits))
            if nxt == cfg.eos_token_id:
                break
            dec.append(nxt)
    return "".join(phonemes[t] for t in dec[1:] if t > 3)


words = [w for w in WORDS.read_text().splitlines() if w.strip()]
out = {}
for prefix in ("us", "gb"):
    model, g, p, cfg = build(prefix)
    out[prefix] = {w: phonemize(model, g, p, cfg, w) for w in words}
OUT.parent.mkdir(parents=True, exist_ok=True)
OUT.write_text(json.dumps(out, ensure_ascii=False, indent=2) + "\n")
print(f"wrote {OUT.relative_to(ROOT)} with {len(words)} words per dialect")
```

- [ ] **Step 3: Run it**

```bash
cd /Users/kevindazoo/aloud/kokoro/MisakiSwift
uv run --python 3.12 --with torch==2.8.0 --with transformers==4.51.2 --with safetensors Tools/reference.py
head -12 Tests/MisakiSwiftTests/Fixtures/fallback-golden.json
```

Expected: `wrote Tests/MisakiSwiftTests/Fixtures/fallback-golden.json with 32 words per dialect`, and the head shows `"blorptastic": "blˌɔɹptˈæstɪk"` under `"us"`.
The first run downloads PyTorch, which takes a few minutes.
`uv` is at `/opt/homebrew/bin/uv`.

- [ ] **Step 4: Commit**

```bash
git add Tools/fallback-words.txt Tools/reference.py Tests/MisakiSwiftTests/Fixtures/fallback-golden.json
git commit -m "Golden phonemes for the fallback network, from the PyTorch model"
```

---

### Task 3: Bring the token type into MisakiSwift and cut the utilities dependency

**Files:**
- Create: `Sources/MisakiSwift/DataStructures/MToken.swift`
- Modify: `Sources/MisakiSwift/English/EnglishG2P.swift:3`
- Modify: `Sources/MisakiSwift/English/Lexicon/Lexicon.swift:3`
- Modify: `Sources/MisakiSwift/English/FallbackNetwork/EnglishFallbackNetwork.swift:3`
- Delete: `Sources/MisakiSwift/Extensions/MLXArray+DebugPrint.swift`
- Modify: `Package.swift`
- Delete: `Package.resolved`

**Interfaces:**
- Produces: `public class MToken` and `public class Underscore` declared in MisakiSwift with the same members as before, so `import MisakiSwift` alone now provides them to the SDK.

The build will be broken from this task until Task 6 replaces the network, because the fallback folder still imports MLX.
That is expected; Tasks 4 and 5 are tested on their own files.

- [ ] **Step 1: Copy the token type in verbatim**

```bash
cd /Users/kevindazoo/aloud/kokoro/MisakiSwift
mkdir -p Sources/MisakiSwift/DataStructures
gh api repos/mlalma/MLXUtilsLibrary/contents/Sources/MLXUtilsLibrary/DataStructures/MToken.swift?ref=0.0.6 -q .content | base64 -d > Sources/MisakiSwift/DataStructures/MToken.swift
head -3 Sources/MisakiSwift/DataStructures/MToken.swift
grep -c "public" Sources/MisakiSwift/DataStructures/MToken.swift
```

Expected: the file starts with `import Foundation` and `import NaturalLanguage`, and the count is 20 or more.
The file declares `public class Underscore` and `public class MToken` with a public `init`, a `convenience init(copying:)` and `CustomStringConvertible` conformances.
Do not edit it: the SDK reads `token.text` and `token.phonemes`, and EnglishG2P constructs `Underscore(...)` and `MToken(...)` with these exact labels.

- [ ] **Step 2: Drop the three imports**

In each of `Sources/MisakiSwift/English/EnglishG2P.swift`, `Sources/MisakiSwift/English/Lexicon/Lexicon.swift` and `Sources/MisakiSwift/English/FallbackNetwork/EnglishFallbackNetwork.swift`, delete the line:

```swift
import MLXUtilsLibrary
```

Then:

```bash
git rm -q Sources/MisakiSwift/Extensions/MLXArray+DebugPrint.swift
grep -rn "MLXUtilsLibrary\|logPrint\|debugPrint" Sources/ || echo "no utilities references remain"
```

Expected: `no utilities references remain`.

- [ ] **Step 3: Rewrite Package.swift**

Replace the whole of `Package.swift` with:

```swift
// swift-tools-version: 6.2
import PackageDescription

let package = Package(
  name: "MisakiSwift",
  platforms: [
    .iOS(.v18), .macOS(.v15),
  ],
  products: [
    // A static library: the app that links this copies one executable into its
    // bundle, and a dynamic product would need to be embedded beside it.
    .library(name: "MisakiSwift", targets: ["MisakiSwift"]),
  ],
  targets: [
    .target(
      name: "MisakiSwift",
      resources: [
        .copy("../../Resources/")
      ]
    ),
    .testTarget(
      name: "MisakiSwiftTests",
      dependencies: ["MisakiSwift"],
      resources: [
        .copy("Fixtures")
      ]
    ),
  ]
)
```

```bash
git rm -q Package.resolved
```

- [ ] **Step 4: Commit the cut**

```bash
git add -A Sources Package.swift
git commit -m "The token type moves in, and the MLX utilities dependency goes"
```

The package does not build yet.
The next three tasks make it build.

---

### Task 4: The safetensors reader

**Files:**
- Create: `Sources/MisakiSwift/English/FallbackNetwork/Safetensors.swift`
- Test: `Tests/MisakiSwiftTests/SafetensorsTests.swift`

**Interfaces:**
- Produces:

```swift
enum Safetensors {
  struct Tensor: Sendable { let shape: [Int]; let data: [Float] }
  enum Error: Swift.Error { case truncated, badHeader, unsupportedDType(String), badOffsets(String) }
  static func load(_ url: URL) throws -> [String: Tensor]
}
```

The format: 8 bytes little-endian `UInt64` header length, then that many bytes of JSON mapping tensor names to `{"dtype": "F32", "shape": [...], "data_offsets": [start, end]}`, with offsets relative to the first byte after the header.
A `__metadata__` key may be present and is skipped.

- [ ] **Step 1: Write the failing test**

Create `Tests/MisakiSwiftTests/SafetensorsTests.swift`:

```swift
import Foundation
import Testing

@testable import MisakiSwift

@Suite struct SafetensorsTests {
  /// The test target's `Bundle.module` holds `Fixtures`, not the library's `Resources`, so
  /// the weights are reached through the library's own accessor.
  private func resource(_ name: String) throws -> URL {
    try #require(Safetensors.bundledWeights(named: name))
  }

  @Test func readsEveryTensorWithItsShape() throws {
    let tensors = try Safetensors.load(resource("us_bart"))
    #expect(tensors.count == 50)
    #expect(tensors["model.shared.weight"]?.shape == [63, 128])
    #expect(tensors["model.shared.weight"]?.data.count == 63 * 128)
    #expect(tensors["model.encoder.embed_positions.weight"]?.shape == [66, 128])
    #expect(tensors["final_logits_bias"]?.shape == [1, 63])
    #expect(tensors["model.decoder.layers.0.fc1.weight"]?.shape == [1024, 128])
    #expect(tensors["__metadata__"] == nil)
  }

  @Test func bothDialectsShareOneLayout() throws {
    let us = try Safetensors.load(resource("us_bart"))
    let gb = try Safetensors.load(resource("gb_bart"))
    #expect(Set(us.keys) == Set(gb.keys))
    for (name, t) in us { #expect(gb[name]?.shape == t.shape, "\(name)") }
  }

  @Test func valuesAreFinite() throws {
    let tensors = try Safetensors.load(resource("gb_bart"))
    for (name, t) in tensors { #expect(t.data.allSatisfy(\.isFinite), "\(name)") }
  }

  @Test func rejectsATruncatedFile() throws {
    let whole = try Data(contentsOf: resource("us_bart"))
    let tmp = FileManager.default.temporaryDirectory.appendingPathComponent("truncated.safetensors")
    try whole.prefix(whole.count - 100).write(to: tmp)
    #expect(throws: Safetensors.Error.self) { try Safetensors.load(tmp) }
  }
}
```

- [ ] **Step 2: Run it to see it fail**

```bash
swift build --target MisakiSwift 2>&1 | grep -c "error:"
```

Expected: a nonzero count, because the fallback folder still imports MLX and `Safetensors` does not exist.
The test cannot run yet; that is fine.
Go straight to the implementation.

- [ ] **Step 3: Implement the reader**

Create `Sources/MisakiSwift/English/FallbackNetwork/Safetensors.swift`:

```swift
import Foundation

/// Reads the fallback network's weights. The safetensors layout is eight bytes of
/// little-endian header length, a JSON header naming each tensor's dtype, shape and byte
/// range, then the tensor bytes back to back. Only float32 is stored here, and only
/// float32 is read.
enum Safetensors {
  struct Tensor: Sendable {
    let shape: [Int]
    let data: [Float]
  }

  enum Error: Swift.Error, Equatable {
    case truncated
    case badHeader
    case unsupportedDType(String)
    case badOffsets(String)
  }

  private struct Entry: Decodable {
    let dtype: String
    let shape: [Int]
    let data_offsets: [Int]
  }

  static func load(_ url: URL) throws -> [String: Tensor] {
    let bytes = try Data(contentsOf: url)
    guard bytes.count >= 8 else { throw Error.truncated }
    let headerLength = bytes.prefix(8).withUnsafeBytes { Int($0.loadUnaligned(as: UInt64.self).littleEndian) }
    guard bytes.count >= 8 + headerLength else { throw Error.truncated }
    let headerData = bytes.subdata(in: 8..<(8 + headerLength))
    guard let raw = try? JSONSerialization.jsonObject(with: headerData) as? [String: Any] else {
      throw Error.badHeader
    }
    let body = bytes.subdata(in: (8 + headerLength)..<bytes.count)
    var out: [String: Tensor] = [:]
    for (name, value) in raw where name != "__metadata__" {
      let entryData = try JSONSerialization.data(withJSONObject: value)
      guard let entry = try? JSONDecoder().decode(Entry.self, from: entryData) else { throw Error.badHeader }
      guard entry.dtype == "F32" else { throw Error.unsupportedDType(entry.dtype) }
      guard entry.data_offsets.count == 2 else { throw Error.badOffsets(name) }
      let start = entry.data_offsets[0]
      let end = entry.data_offsets[1]
      let count = entry.shape.reduce(1, *)
      guard start >= 0, end >= start, end <= body.count, end - start == count * 4 else {
        throw Error.badOffsets(name)
      }
      let data = body.subdata(in: start..<end).withUnsafeBytes { buffer -> [Float] in
        var floats = [Float](repeating: 0, count: count)
        for i in 0..<count {
          floats[i] = Float(bitPattern: buffer.loadUnaligned(fromByteOffset: i * 4, as: UInt32.self).littleEndian)
        }
        return floats
      }
      out[name] = Tensor(shape: entry.shape, data: data)
    }
    return out
  }

  /// The bundled weight file for one dialect, "us_bart" or "gb_bart".
  static func bundledWeights(named name: String) -> URL? {
    Bundle.module.url(forResource: name, withExtension: "safetensors", subdirectory: "Resources")
  }

  /// The bundled network config for one dialect, "us_bart_config" or "gb_bart_config".
  static func bundledConfig(named name: String) -> URL? {
    Bundle.module.url(forResource: name, withExtension: "json", subdirectory: "Resources")
  }
}
```

The `Error` enum's `Equatable` conformance is what lets the truncated-file test use `#expect(throws:)` with the type.

- [ ] **Step 4: Temporarily park the MLX files so the reader can be tested alone**

The six MLX files block the build until Task 6 deletes them.
Move them aside for now, outside the package so SwiftPM does not see them:

```bash
cd /Users/kevindazoo/aloud/kokoro/MisakiSwift
mkdir -p /Users/kevindazoo/aloud/kokoro/parked
for f in BARTModel BARTEncoderLayer BARTDecoderLayer BARTLayerNorm MultiHeadAttention FeedForward EnglishFallbackNetwork; do
  mv Sources/MisakiSwift/English/FallbackNetwork/$f.swift /Users/kevindazoo/aloud/kokoro/parked/$f.swift
done
ls /Users/kevindazoo/aloud/kokoro/parked
```

Then, so that `EnglishG2P.swift` still compiles without the network, add a stand-in at `Sources/MisakiSwift/English/FallbackNetwork/EnglishFallbackNetwork.swift`:

```swift
import Foundation

/// Stand-in while the Accelerate network is built. Replaced in Task 6.
final class EnglishFallbackNetwork {
  static let unknownTokenId = 3
  init(british: Bool) {}
  func callAsFunction(_ word: MToken) -> (phoneme: String, rating: Int) { ("", 1) }
}
```

- [ ] **Step 5: Run the reader tests**

```bash
swift test --filter SafetensorsTests 2>&1 | grep -E "Test .* (passed|failed)|error:|Suite .* (passed|failed)" | tail -8
```

Expected: all four tests pass.
If `Bundle.module` complains at runtime that the resource bundle is missing, run `swift package clean` and try again; a stale resource bundle from the old target layout causes it.

- [ ] **Step 6: Commit**

```bash
git add Sources/MisakiSwift/English/FallbackNetwork Tests/MisakiSwiftTests/SafetensorsTests.swift
git commit -m "A safetensors reader for the fallback network's weights"
```

The parked MLX files are outside the repository and are deleted for good in Task 6.

---

### Task 5: The matrix type and the network

**Files:**
- Create: `Sources/MisakiSwift/English/FallbackNetwork/Matrix.swift`
- Create: `Sources/MisakiSwift/English/FallbackNetwork/BARTNetwork.swift`
- Test: `Tests/MisakiSwiftTests/FallbackNetworkTests.swift` (the matrix tests; the golden test is added in Task 6)

**Interfaces:**
- Consumes: `Safetensors.Tensor` from Task 4.
- Produces:

```swift
struct Matrix: Sendable {
  let rows: Int
  let cols: Int
  var data: [Float]                          // row-major, rows * cols
  init(rows: Int, cols: Int)                 // zeros
  init(rows: Int, cols: Int, data: [Float])
  init(_ tensor: Safetensors.Tensor) throws  // requires a 2-D shape
  subscript(row: Int, col: Int) -> Float
  func row(_ i: Int) -> [Float]
  func columns(from: Int, count: Int) -> Matrix
  mutating func setColumns(from: Int, _ block: Matrix)
  func matmul(_ b: Matrix) -> Matrix            // [n,k] x [k,m]
  func matmulTransposed(_ b: Matrix) -> Matrix  // [n,d] x [m,d]^T
  func adding(_ b: Matrix) -> Matrix
  func adding(bias: [Float]) -> Matrix          // to every row
  func scaled(by s: Float) -> Matrix
  func softmaxRows() -> Matrix
  func layerNormRows(weight: [Float], bias: [Float], eps: Float) -> Matrix
  func gelu() -> Matrix
}

struct BARTNetwork: Sendable {
  init(config: BARTConfig, tensors: [String: Safetensors.Tensor]) throws
  func generate(_ inputIds: [Int]) -> [Int]   // generated ids, without BOS, at most 49
}
```

The semantics to reproduce, taken from the MLX code and confirmed against Transformers:

- Token embedding rows come from `model.shared.weight`.
- Position rows come from `embed_positions.weight` at index `position + 2`.
- After embedding, `layernorm_embedding` is applied before the first layer.
- Each layer is post-norm: `h = LN(h + attn(h))`, then for the decoder `h = LN(h + cross(h, enc))`, then `h = LN(h + fc2(gelu(fc1(h))))`.
- Attention: `q`, `k`, `v` and `out` are linear layers with bias; scores are `q k^T / sqrt(headDim)`; softmax over keys; no masks. The last decoder row is the only one read, and without a causal mask it attends to every row, which is what the reference does too.
- Linear layers store weight as `[out, in]`, so `y = x W^T + b`.
- Layer norm epsilon is `1e-5`, with the population variance.
- gelu is the exact form `x * (1 + erf(x / sqrt(2))) / 2`.
- Logits for the last row are `h · shared^T + final_logits_bias`.
- Generation: start with `[bos]`; loop `i` in `0..<50`; when `i == 49` stop without appending; otherwise take the argmax, stop on `eos`, else append. Ties go to the lowest index.

- [ ] **Step 1: Write the failing matrix tests**

Create `Tests/MisakiSwiftTests/FallbackNetworkTests.swift`:

```swift
import Foundation
import Testing

@testable import MisakiSwift

@Suite struct MatrixTests {
  @Test func matmulMatchesByHand() {
    let a = Matrix(rows: 2, cols: 3, data: [1, 2, 3, 4, 5, 6])
    let b = Matrix(rows: 3, cols: 2, data: [7, 8, 9, 10, 11, 12])
    let c = a.matmul(b)
    #expect(c.rows == 2 && c.cols == 2)
    #expect(c.data == [58, 64, 139, 154])
  }

  @Test func matmulTransposedIsAgainstRows() {
    let a = Matrix(rows: 2, cols: 3, data: [1, 2, 3, 4, 5, 6])
    let b = Matrix(rows: 2, cols: 3, data: [1, 0, 0, 0, 1, 0])
    let c = a.matmulTransposed(b)
    #expect(c.data == [1, 2, 4, 5])
  }

  @Test func softmaxRowsSumToOne() {
    let m = Matrix(rows: 2, cols: 3, data: [1, 2, 3, 1000, 1000, 1000]).softmaxRows()
    #expect(abs(m.row(0).reduce(0, +) - 1) < 1e-5)
    #expect(m.row(1).allSatisfy { abs($0 - 1.0 / 3) < 1e-5 })
    #expect(m[0, 2] > m[0, 1] && m[0, 1] > m[0, 0])
  }

  @Test func layerNormZeroMeansUnitVariance() {
    let m = Matrix(rows: 1, cols: 4, data: [1, 2, 3, 4])
      .layerNormRows(weight: [1, 1, 1, 1], bias: [0, 0, 0, 0], eps: 0)
    let r = m.row(0)
    #expect(abs(r.reduce(0, +)) < 1e-5)
    let variance = r.map { $0 * $0 }.reduce(0, +) / 4
    #expect(abs(variance - 1) < 1e-4)
  }

  @Test func geluIsTheExactForm() {
    let m = Matrix(rows: 1, cols: 3, data: [-1, 0, 1]).gelu()
    #expect(abs(m[0, 0] - (-0.15865526)) < 1e-6)
    #expect(m[0, 1] == 0)
    #expect(abs(m[0, 2] - 0.84134474) < 1e-6)
  }

  @Test func columnsRoundTrip() {
    let m = Matrix(rows: 2, cols: 4, data: [1, 2, 3, 4, 5, 6, 7, 8])
    let block = m.columns(from: 1, count: 2)
    #expect(block.data == [2, 3, 6, 7])
    var target = Matrix(rows: 2, cols: 4)
    target.setColumns(from: 1, block)
    #expect(target.data == [0, 2, 3, 0, 0, 6, 7, 0])
  }
}

@Suite struct BARTNetworkTests {
  @Test func generatesSomethingAndStops() throws {
    let url = try #require(Safetensors.bundledWeights(named: "us_bart"))
    let configURL = try #require(Safetensors.bundledConfig(named: "us_bart_config"))
    let config = try JSONDecoder().decode(BARTConfig.self, from: Data(contentsOf: configURL))
    let net = try BARTNetwork(config: config, tensors: Safetensors.load(url))
    // "b", "l", "o", "r", "p" spelled through grapheme_chars, wrapped in BOS and EOS.
    let graphemes = Array(config.graphemeChars)
    let ids = [config.bosTokenId] + "blorp".map { graphemes.firstIndex(of: $0)! } + [config.eosTokenId]
    let out = net.generate(ids)
    #expect(!out.isEmpty)
    #expect(out.count < 50)
    #expect(!out.contains(config.eosTokenId))
    #expect(out.allSatisfy { $0 > 3 && $0 < config.vocabSize })
  }
}
```

- [ ] **Step 2: Run to see them fail**

```bash
swift test --filter "MatrixTests|BARTNetworkTests" 2>&1 | grep -E "error:" | head -3
```

Expected: `cannot find 'Matrix' in scope`.

- [ ] **Step 3: Implement Matrix**

Create `Sources/MisakiSwift/English/FallbackNetwork/Matrix.swift`:

```swift
import Accelerate
import Foundation

/// A row-major float matrix with the few operations the fallback network needs. Every
/// operation returns a new matrix; the network is small enough that copying is nothing.
struct Matrix: Sendable {
  let rows: Int
  let cols: Int
  var data: [Float]

  init(rows: Int, cols: Int) {
    self.rows = rows
    self.cols = cols
    self.data = [Float](repeating: 0, count: rows * cols)
  }

  init(rows: Int, cols: Int, data: [Float]) {
    precondition(data.count == rows * cols, "Matrix \(rows)x\(cols) given \(data.count) values")
    self.rows = rows
    self.cols = cols
    self.data = data
  }

  enum ShapeError: Error { case notTwoDimensional([Int]) }

  init(_ tensor: Safetensors.Tensor) throws {
    guard tensor.shape.count == 2 else { throw ShapeError.notTwoDimensional(tensor.shape) }
    self.init(rows: tensor.shape[0], cols: tensor.shape[1], data: tensor.data)
  }

  subscript(row: Int, col: Int) -> Float {
    data[row * cols + col]
  }

  func row(_ i: Int) -> [Float] {
    Array(data[(i * cols)..<((i + 1) * cols)])
  }

  func columns(from: Int, count: Int) -> Matrix {
    var out = Matrix(rows: rows, cols: count)
    for r in 0..<rows {
      for c in 0..<count { out.data[r * count + c] = data[r * cols + from + c] }
    }
    return out
  }

  mutating func setColumns(from: Int, _ block: Matrix) {
    precondition(block.rows == rows)
    for r in 0..<rows {
      for c in 0..<block.cols { data[r * cols + from + c] = block.data[r * block.cols + c] }
    }
  }

  /// `self` [n,k] times `b` [k,m].
  func matmul(_ b: Matrix) -> Matrix {
    precondition(cols == b.rows)
    var out = Matrix(rows: rows, cols: b.cols)
    data.withUnsafeBufferPointer { a in
      b.data.withUnsafeBufferPointer { bp in
        out.data.withUnsafeMutableBufferPointer { c in
          cblas_sgemm(
            CblasRowMajor, CblasNoTrans, CblasNoTrans,
            Int32(rows), Int32(b.cols), Int32(cols),
            1, a.baseAddress, Int32(cols),
            bp.baseAddress, Int32(b.cols),
            0, c.baseAddress, Int32(b.cols))
        }
      }
    }
    return out
  }

  /// `self` [n,d] times the transpose of `b` [m,d], giving [n,m]. This is both a linear
  /// layer against a `[out,in]` weight and the query-key product of attention.
  func matmulTransposed(_ b: Matrix) -> Matrix {
    precondition(cols == b.cols)
    var out = Matrix(rows: rows, cols: b.rows)
    data.withUnsafeBufferPointer { a in
      b.data.withUnsafeBufferPointer { bp in
        out.data.withUnsafeMutableBufferPointer { c in
          cblas_sgemm(
            CblasRowMajor, CblasNoTrans, CblasTrans,
            Int32(rows), Int32(b.rows), Int32(cols),
            1, a.baseAddress, Int32(cols),
            bp.baseAddress, Int32(b.cols),
            0, c.baseAddress, Int32(b.rows))
        }
      }
    }
    return out
  }

  func adding(_ b: Matrix) -> Matrix {
    precondition(rows == b.rows && cols == b.cols)
    return Matrix(rows: rows, cols: cols, data: vDSP.add(data, b.data))
  }

  func adding(bias: [Float]) -> Matrix {
    precondition(bias.count == cols)
    var out = self
    for r in 0..<rows {
      for c in 0..<cols { out.data[r * cols + c] += bias[c] }
    }
    return out
  }

  func scaled(by s: Float) -> Matrix {
    Matrix(rows: rows, cols: cols, data: vDSP.multiply(s, data))
  }

  func softmaxRows() -> Matrix {
    var out = self
    for r in 0..<rows {
      let range = (r * cols)..<((r + 1) * cols)
      let top = out.data[range].max() ?? 0
      var sum: Float = 0
      for i in range {
        let e = expf(out.data[i] - top)
        out.data[i] = e
        sum += e
      }
      for i in range { out.data[i] /= sum }
    }
    return out
  }

  func layerNormRows(weight: [Float], bias: [Float], eps: Float) -> Matrix {
    precondition(weight.count == cols && bias.count == cols)
    var out = self
    for r in 0..<rows {
      let range = (r * cols)..<((r + 1) * cols)
      var mean: Float = 0
      var meanOfSquares: Float = 0
      vDSP_measqv(Array(data[range]), 1, &meanOfSquares, vDSP_Length(cols))
      vDSP_meanv(Array(data[range]), 1, &mean, vDSP_Length(cols))
      let variance = max(meanOfSquares - mean * mean, 0)
      let inv = 1 / (variance + eps).squareRoot()
      for (j, i) in range.enumerated() {
        out.data[i] = (data[i] - mean) * inv * weight[j] + bias[j]
      }
    }
    return out
  }

  /// The exact gelu, `x * (1 + erf(x / sqrt 2)) / 2`, the form MLXNN and Transformers use here.
  func gelu() -> Matrix {
    Matrix(rows: rows, cols: cols, data: data.map { $0 * (1 + erff($0 / Float(2).squareRoot())) / 2 })
  }
}
```

The variance in `layerNormRows` is computed as `E[x²] - E[x]²`, which is the population variance the reference uses.
If the Accelerate SDK on the machine declares `cblas_sgemm` sizes as `Int` rather than `Int32`, drop the `Int32(...)` casts; nothing else changes.

- [ ] **Step 4: Run the matrix tests**

```bash
swift test --filter MatrixTests 2>&1 | grep -E "Test .* (passed|failed)|error:" | tail -8
```

Expected: six passes.

- [ ] **Step 5: Implement the network**

Create `Sources/MisakiSwift/English/FallbackNetwork/BARTNetwork.swift`:

```swift
import Foundation

/// The fallback grapheme-to-phoneme network: a one-layer BART encoder and decoder with a
/// tied output head, run greedily. It reproduces the PyTorch model the weights were
/// trained as, and the MLX port that preceded this file, token for token.
struct BARTNetwork: Sendable {
  enum WeightError: Error { case missing(String) }

  struct Dense: Sendable {
    let weight: Matrix  // [out, in]
    let bias: [Float]
    func callAsFunction(_ x: Matrix) -> Matrix {
      x.matmulTransposed(weight).adding(bias: bias)
    }
  }

  struct Norm: Sendable {
    let weight: [Float]
    let bias: [Float]
    static let eps: Float = 1e-5
    func callAsFunction(_ x: Matrix) -> Matrix {
      x.layerNormRows(weight: weight, bias: bias, eps: Self.eps)
    }
  }

  struct Attention: Sendable {
    let q: Dense
    let k: Dense
    let v: Dense
    let out: Dense
    let heads: Int

    func callAsFunction(_ query: Matrix, keyValue: Matrix) -> Matrix {
      let qp = q(query)
      let kp = k(keyValue)
      let vp = v(keyValue)
      let dim = qp.cols / heads
      let scale = 1 / Float(dim).squareRoot()
      var merged = Matrix(rows: qp.rows, cols: qp.cols)
      for h in 0..<heads {
        let qh = qp.columns(from: h * dim, count: dim)
        let kh = kp.columns(from: h * dim, count: dim)
        let vh = vp.columns(from: h * dim, count: dim)
        let weights = qh.matmulTransposed(kh).scaled(by: scale).softmaxRows()
        merged.setColumns(from: h * dim, weights.matmul(vh))
      }
      return out(merged)
    }
  }

  struct Layer: Sendable {
    let selfAttention: Attention
    let selfNorm: Norm
    let crossAttention: Attention?
    let crossNorm: Norm?
    let fc1: Dense
    let fc2: Dense
    let finalNorm: Norm

    func callAsFunction(_ x: Matrix, encoder: Matrix?) -> Matrix {
      var h = selfNorm(x.adding(selfAttention(x, keyValue: x)))
      if let crossAttention, let crossNorm, let encoder {
        h = crossNorm(h.adding(crossAttention(h, keyValue: encoder)))
      }
      return finalNorm(h.adding(fc2(fc1(h).gelu())))
    }
  }

  let config: BARTConfig
  let shared: Matrix
  let encoderPositions: Matrix
  let decoderPositions: Matrix
  let encoderNorm: Norm
  let decoderNorm: Norm
  let encoderLayers: [Layer]
  let decoderLayers: [Layer]
  let logitBias: [Float]

  init(config: BARTConfig, tensors: [String: Safetensors.Tensor]) throws {
    func tensor(_ name: String) throws -> Safetensors.Tensor {
      guard let t = tensors[name] else { throw WeightError.missing(name) }
      return t
    }
    func matrix(_ name: String) throws -> Matrix { try Matrix(try tensor(name)) }
    func vector(_ name: String) throws -> [Float] { try tensor(name).data }
    func dense(_ prefix: String) throws -> Dense {
      Dense(weight: try matrix(prefix + ".weight"), bias: try vector(prefix + ".bias"))
    }
    func norm(_ prefix: String) throws -> Norm {
      Norm(weight: try vector(prefix + ".weight"), bias: try vector(prefix + ".bias"))
    }
    func attention(_ prefix: String, heads: Int) throws -> Attention {
      Attention(
        q: try dense(prefix + ".q_proj"), k: try dense(prefix + ".k_proj"),
        v: try dense(prefix + ".v_proj"), out: try dense(prefix + ".out_proj"), heads: heads)
    }
    func layer(_ prefix: String, heads: Int, cross: Bool) throws -> Layer {
      Layer(
        selfAttention: try attention(prefix + ".self_attn", heads: heads),
        selfNorm: try norm(prefix + ".self_attn_layer_norm"),
        crossAttention: cross ? try attention(prefix + ".encoder_attn", heads: heads) : nil,
        crossNorm: cross ? try norm(prefix + ".encoder_attn_layer_norm") : nil,
        fc1: try dense(prefix + ".fc1"),
        fc2: try dense(prefix + ".fc2"),
        finalNorm: try norm(prefix + ".final_layer_norm"))
    }

    self.config = config
    self.shared = try matrix("model.shared.weight")
    self.encoderPositions = try matrix("model.encoder.embed_positions.weight")
    self.decoderPositions = try matrix("model.decoder.embed_positions.weight")
    self.encoderNorm = try norm("model.encoder.layernorm_embedding")
    self.decoderNorm = try norm("model.decoder.layernorm_embedding")
    self.encoderLayers = try (0..<config.encoderLayers).map {
      try layer("model.encoder.layers.\($0)", heads: config.encoderAttentionHeads, cross: false)
    }
    self.decoderLayers = try (0..<config.decoderLayers).map {
      try layer("model.decoder.layers.\($0)", heads: config.decoderAttentionHeads, cross: true)
    }
    self.logitBias = try vector("final_logits_bias")
  }

  /// BART's position table starts two rows in.
  private static let positionOffset = 2

  private func embed(_ ids: [Int], positions table: Matrix, norm: Norm) -> Matrix {
    var h = Matrix(rows: ids.count, cols: shared.cols)
    for (i, id) in ids.enumerated() {
      let token = shared.row(id)
      let position = table.row(i + Self.positionOffset)
      for c in 0..<shared.cols { h.data[i * shared.cols + c] = token[c] + position[c] }
    }
    return norm(h)
  }

  func encode(_ ids: [Int]) -> Matrix {
    var h = embed(ids, positions: encoderPositions, norm: encoderNorm)
    for layer in encoderLayers { h = layer(h, encoder: nil) }
    return h
  }

  /// Logits over the vocabulary for the last decoder position.
  func decodeLast(_ ids: [Int], encoder: Matrix) -> [Float] {
    var h = embed(ids, positions: decoderPositions, norm: decoderNorm)
    for layer in decoderLayers { h = layer(h, encoder: encoder) }
    let last = Matrix(rows: 1, cols: h.cols, data: h.row(h.rows - 1))
    return last.matmulTransposed(shared).adding(bias: logitBias).row(0)
  }

  /// Greedy decoding, the way the MLX port did it: at most 49 generated tokens, stopping at
  /// EOS, ties to the lowest index.
  func generate(_ inputIds: [Int]) -> [Int] {
    let encoder = encode(inputIds)
    var decoded = [config.bosTokenId]
    var out: [Int] = []
    let maxLength = 50
    for i in 0..<maxLength {
      if i == maxLength - 1 { break }
      let logits = decodeLast(decoded, encoder: encoder)
      var best = 0
      for (j, v) in logits.enumerated() where v > logits[best] { best = j }
      if best == config.eosTokenId { break }
      out.append(best)
      decoded.append(best)
    }
    return out
  }
}
```

- [ ] **Step 6: Run the network test**

```bash
swift test --filter BARTNetworkTests 2>&1 | grep -E "Test .* (passed|failed)|error:" | tail -4
```

Expected: `generatesSomethingAndStops` passes.

- [ ] **Step 7: Commit**

```bash
git add Sources/MisakiSwift/English/FallbackNetwork/Matrix.swift Sources/MisakiSwift/English/FallbackNetwork/BARTNetwork.swift Sources/MisakiSwift/English/FallbackNetwork/Safetensors.swift Tests/MisakiSwiftTests/FallbackNetworkTests.swift
git commit -m "The fallback network on Accelerate"
```

---

### Task 6: Wire the network in and prove it against the golden file

**Files:**
- Modify: `Sources/MisakiSwift/English/FallbackNetwork/EnglishFallbackNetwork.swift` (replace the stand-in)
- Modify: `Tests/MisakiSwiftTests/FallbackNetworkTests.swift` (add the golden suite)

**Interfaces:**
- Consumes: `BARTNetwork`, `Safetensors`, `fallback-golden.json`.
- Produces: `final class EnglishFallbackNetwork` with the upstream API, `init(british: Bool)` and `callAsFunction(_ word: MToken) -> (phoneme: String, rating: Int)`, plus `static let unknownTokenId = 3`.

- [ ] **Step 1: Add the golden test**

Append to `Tests/MisakiSwiftTests/FallbackNetworkTests.swift`:

```swift
@Suite struct FallbackGoldenTests {
  private func golden() throws -> [String: [String: String]] {
    let url = try #require(Bundle.module.url(forResource: "fallback-golden", withExtension: "json", subdirectory: "Fixtures"))
    return try JSONDecoder().decode([String: [String: String]].self, from: Data(contentsOf: url))
  }

  private func token(_ word: String) -> MToken {
    MToken(text: word, tokenRange: word.startIndex..<word.endIndex, whitespace: "")
  }

  @Test func americanMatchesThePyTorchModel() throws {
    let expected = try #require(try golden()["us"])
    let net = EnglishFallbackNetwork(british: false)
    for (word, phonemes) in expected.sorted(by: { $0.key < $1.key }) {
      #expect(net(token(word)).phoneme == phonemes, "us \(word)")
    }
  }

  @Test func britishMatchesThePyTorchModel() throws {
    let expected = try #require(try golden()["gb"])
    let net = EnglishFallbackNetwork(british: true)
    for (word, phonemes) in expected.sorted(by: { $0.key < $1.key }) {
      #expect(net(token(word)).phoneme == phonemes, "gb \(word)")
    }
  }

  @Test func ratingIsOne() {
    #expect(EnglishFallbackNetwork(british: false)(token("blorptastic")).rating == 1)
  }
}
```

- [ ] **Step 2: Run to see it fail**

```bash
swift test --filter FallbackGoldenTests 2>&1 | grep -E "Test .* (passed|failed)" | tail -4
```

Expected: the two dialect tests fail, because the stand-in returns an empty string.

- [ ] **Step 3: Replace the stand-in**

Replace the whole of `Sources/MisakiSwift/English/FallbackNetwork/EnglishFallbackNetwork.swift` with:

```swift
import Foundation

/// Pronounces a word the dictionaries did not know, with the small BART network shipped
/// beside them. Loaded once per dialect; the network is a value and the class only caches it.
final class EnglishFallbackNetwork {
  static let unknownTokenId = 3

  private let configuration: BARTConfig
  private let network: BARTNetwork
  private let graphemeToToken: [Character: Int]
  private let tokenToPhoneme: [Int: Character]
  private let british: Bool

  init(british: Bool) {
    self.british = british
    let prefix = british ? "gb" : "us"
    guard let configURL = Safetensors.bundledConfig(named: "\(prefix)_bart_config"),
      let configData = try? Data(contentsOf: configURL),
      let configuration = try? JSONDecoder().decode(BARTConfig.self, from: configData)
    else {
      fatalError("MisakiSwift: the bundled \(prefix)_bart_config.json is missing or unreadable")
    }
    guard let weightsURL = Safetensors.bundledWeights(named: "\(prefix)_bart"),
      let tensors = try? Safetensors.load(weightsURL),
      let network = try? BARTNetwork(config: configuration, tensors: tensors)
    else {
      fatalError("MisakiSwift: the bundled \(prefix)_bart.safetensors is missing or unreadable")
    }
    self.configuration = configuration
    self.network = network

    var graphemes: [Character: Int] = [:]
    for (index, grapheme) in configuration.graphemeChars.enumerated() { graphemes[grapheme] = index }
    self.graphemeToToken = graphemes

    var phonemes: [Int: Character] = [:]
    for (index, phoneme) in configuration.phonemeChars.enumerated() { phonemes[index] = phoneme }
    self.tokenToPhoneme = phonemes
  }

  private func graphemesToTokens(_ graphemes: String) -> [Int] {
    var tokens = [configuration.bosTokenId]
    for char in graphemes {
      tokens.append(graphemeToToken[char] ?? Self.unknownTokenId)
    }
    tokens.append(configuration.eosTokenId)
    return tokens
  }

  private func tokensToPhonemes(_ tokens: [Int]) -> String {
    var phonemes = ""
    for token in tokens where token > Self.unknownTokenId {
      if let phoneme = tokenToPhoneme[token] { phonemes.append(phoneme) }
    }
    return phonemes
  }

  func callAsFunction(_ word: MToken) -> (phoneme: String, rating: Int) {
    let generated = network.generate(graphemesToTokens(word.text))
    return (tokensToPhonemes(generated), 1)
  }
}
```

- [ ] **Step 4: Run the golden tests**

```bash
swift test --filter FallbackGoldenTests 2>&1 | grep -E "Test .* (passed|failed)|Expectation failed" | tail -12
```

Expected: three passes.
If one word differs, print both strings and compare the first differing phoneme.
A single flipped token on one word points at a near tie in the logits; check `layerNormRows` uses the population variance and that `gelu` is the erf form, since those are the two places a subtly different formula still produces plausible output.
A difference on every word points at a layout error, most likely `matmulTransposed` arguments or the position offset.

- [ ] **Step 5: Run the whole suite and confirm nothing from MLX remains**

```bash
swift test 2>&1 | grep -E "Test .* (passed|failed)|Suite .* (passed|failed)|error:" | tail -20
grep -rn "import MLX\|MLXArray\|MLXNN" Sources Tests || echo "no MLX left"
rm -rf /Users/kevindazoo/aloud/kokoro/parked
```

Expected: every test passes, including upstream's `testStrings_BritishPhonetization` and `testStrings_AmericanPhonetization`, and `no MLX left`.
If the two upstream string tests now differ from their expected strings, a word in those sentences reached the fallback, and the expected strings were produced by the MLX network.
In that case the golden file, not the upstream expectation, is the reference: run Task 2's generator on the disputed word, and if the Accelerate output matches PyTorch, update the upstream expectation and say so in the commit message.

- [ ] **Step 6: Commit**

```bash
git add -A
git commit -m "The fallback network runs on Accelerate, matching the PyTorch model on the golden list"
```

---

### Task 7: Verify a plain build from a clean checkout and push the fork

**Files:**
- None new.

**Interfaces:**
- Produces: the pushed revision of `kevinxu-cmd/MisakiSwift`, referred to below as `MISAKI_REV`.

- [ ] **Step 1: Confirm the package resolves with no dependencies**

```bash
cd /Users/kevindazoo/aloud/kokoro/MisakiSwift
swift package clean
swift package resolve
ls Package.resolved 2>/dev/null || echo "no Package.resolved, no dependencies"
swift build 2>&1 | tail -1
```

Expected: `no Package.resolved, no dependencies` and `Build complete!`.
A build that once took a minute now takes a few seconds, because nothing but MisakiSwift is compiled.

- [ ] **Step 2: Push**

```bash
git push origin main
MISAKI_REV=$(git rev-parse HEAD)
echo "MISAKI_REV=$MISAKI_REV"
```

Write the printed revision down.
Task 8 pins it, and plan 3 pins it again from Aloud.

---

### Task 8: Fork the SDK and repoint it at the Misaki fork

**Files:**
- Modify: `swift-tts/Package.swift:16-19`
- Regenerate: `swift-tts/Package.resolved`
- Modify: `swift-tts/Tests/KokoroTTSTests/KokoroMisakiPhonemizerTests.swift`
- Create: `Package.swift` at the repository root

**Interfaces:**
- Consumes: `MISAKI_REV` from Task 7.
- Produces: the fork `https://github.com/kevinxu-cmd/kokoro-coreml`, branch `aloud`, at a revision referred to as `SDK_REV`, with a root manifest exposing the products `KokoroTTS` and `KokoroPipeline`. Aloud depends on it as `.package(url: "https://github.com/kevinxu-cmd/kokoro-coreml.git", revision: "SDK_REV")` with the product `KokoroTTS`.

Upstream keeps two packages in subdirectories, `swift/` and `swift-tts/`, and SwiftPM cannot depend on a subdirectory of a remote repository.
A manifest at the root that names the same sources makes the fork consumable by URL and revision, which is how the spec says Aloud pins it.
The two subdirectory manifests stay as they are so upstream's tests keep running from their own directories.

- [ ] **Step 1: Fork and clone**

```bash
cd /Users/kevindazoo/aloud/kokoro
gh repo fork mattmireles/kokoro-coreml --clone=false --default-branch-only
git clone https://github.com/kevinxu-cmd/kokoro-coreml.git
cd kokoro-coreml
git checkout -b aloud fa57641e3e5d29b1721c1c06483da030b91a04d2
```

Expected: a branch `aloud` at the upstream revision this plan was written against.
If the fork's `main` has moved past it, the checkout still lands on the pinned revision.

- [ ] **Step 2: Repoint the phonemizer dependency**

In `swift-tts/Package.swift`, replace:

```swift
        .package(
            url: "https://github.com/mattmireles/MisakiSwift",
            revision: "3a27756a780fc138e328a96e533fb440a3419d5b"
        ),
```

with, substituting the revision from Task 7:

```swift
        // Aloud's fork: the fallback network runs on Accelerate rather than MLX, so the
        // package builds and runs from a plain `swift build`.
        .package(
            url: "https://github.com/kevinxu-cmd/MisakiSwift",
            revision: "MISAKI_REV"
        ),
```

- [ ] **Step 3: Resolve and check that MLX is gone**

```bash
cd /Users/kevindazoo/aloud/kokoro/kokoro-coreml/swift-tts
rm -f Package.resolved
swift package resolve
grep -o '"identity" : "[a-z-]*"' Package.resolved
```

Expected: exactly one identity, `misakiswift`.
If `mlx-swift`, `mlxutilslibrary`, `swift-numerics` or `zipfoundation` appear, the Misaki fork still declares a dependency; go back to Task 3 Step 3.

- [ ] **Step 4: Build**

```bash
swift build 2>&1 | tail -3
```

Expected: `Build complete!`.
The `KokoroMisakiPhonemizer.swift` source needs no change: it imports `MisakiSwift`, and `MToken` now comes from there.

- [ ] **Step 5: Un-skip the phonemizer runtime tests**

In `swift-tts/Tests/KokoroTTSTests/KokoroMisakiPhonemizerTests.swift`, delete the `runtimeTestsFlag` property and the `skipUnlessRuntimeProbeEnabled()` method with their doc comments, and delete the two lines `try skipUnlessRuntimeProbeEnabled()` from `testUSPhonemizerReturnsNonEmptyPhonemes` and `testBritishPhonemizerReturnsNonEmptyPhonemes`.
Add a third test beside them that forces the fallback:

```swift
    /// Verifies an unknown word is pronounced rather than dropped: the fallback network
    /// runs on Accelerate in Aloud's fork, so this needs no MLX environment.
    func testUnknownWordGoesThroughTheFallback() throws {
        let phonemizer = KokoroMisakiPhonemizer()

        let result = try phonemizer.phonemize("The blorptastic grimbleworth.")

        XCTAssertEqual(result.droppedTokens, 0)
        XCTAssertTrue(result.phonemes.contains("blˌɔɹptˈæstɪk"), result.phonemes)
    }
```

- [ ] **Step 6: Run the SDK's tests**

```bash
swift test 2>&1 | grep -E "Executed|error:|failed" | tail -10
```

Expected: every test executes with 0 failures, including the three phonemizer runtime tests.
Tests that need a real model bundle build a synthetic fixture for themselves and do not need a download.
If a test fails for a reason unrelated to the phonemizer, such as a sandbox path it cannot write, note it in the commit message and report it; do not skip it silently.

- [ ] **Step 7: Add the root manifest**

Create `Package.swift` at the repository root, substituting `MISAKI_REV`:

```swift
// swift-tools-version: 5.9
// Aloud's fork: one manifest at the root so the SDK can be pinned by URL and revision.
// Upstream keeps `swift/` and `swift-tts/` as separate packages, and they stay that way;
// this names the same sources from one level up.
import PackageDescription

let package = Package(
    name: "kokoro-coreml",
    platforms: [
        .macOS("15.0"),
        .iOS("18.0"),
    ],
    products: [
        .library(name: "KokoroTTS", targets: ["KokoroTTS"]),
        .library(name: "KokoroPipeline", targets: ["KokoroPipeline"]),
    ],
    dependencies: [
        .package(
            url: "https://github.com/kevinxu-cmd/MisakiSwift",
            revision: "MISAKI_REV"
        ),
    ],
    targets: [
        .target(
            name: "KokoroPipeline",
            path: "swift/Sources/KokoroPipeline"
        ),
        .target(
            name: "KokoroTTS",
            dependencies: [
                "KokoroPipeline",
                .product(name: "MisakiSwift", package: "MisakiSwift"),
            ],
            path: "swift-tts/Sources/KokoroTTS",
            resources: [
                .process("Resources"),
            ]
        ),
    ]
)
```

```bash
cd /Users/kevindazoo/aloud/kokoro/kokoro-coreml
swift build 2>&1 | tail -3
grep -o '"identity" : "[a-z-]*"' Package.resolved
```

Expected: `Build complete!` and one identity, `misakiswift`.
If SwiftPM complains that `swift/` or `swift-tts/` contains a nested package, it is because a target path was mistyped; the paths above point at `Sources` folders, which SwiftPM accepts inside directories that also hold a manifest.

- [ ] **Step 8: Commit and push**

```bash
cd /Users/kevindazoo/aloud/kokoro/kokoro-coreml
git add Package.swift Package.resolved swift-tts/Package.swift swift-tts/Package.resolved swift-tts/Tests/KokoroTTSTests/KokoroMisakiPhonemizerTests.swift
git commit -m "The phonemizer comes from Aloud's MisakiSwift fork, and a root manifest pins the SDK by URL"
git push -u origin aloud
SDK_REV=$(git rev-parse HEAD)
echo "SDK_REV=$SDK_REV"
```

Write the printed revision down beside `MISAKI_REV`.

---

### Task 9: Prove the SDK is consumable from a fresh package with `swift build`

**Files:**
- Create: `/Users/kevindazoo/aloud/kokoro/consumer/Package.swift` and `Sources/consumer/main.swift` (throwaway, not committed anywhere)

**Interfaces:**
- Consumes: `SDK_REV`.
- Produces: confidence that plan 3's `Package.swift` line will resolve and link, and the exact dependency declaration plan 3 uses.

This rehearses exactly what Aloud's manifest will do: a remote dependency on the fork by URL and revision, in Swift 6 language mode as Aloud builds.

- [ ] **Step 1: Make the consumer**

```bash
mkdir -p /Users/kevindazoo/aloud/kokoro/consumer/Sources/consumer
cd /Users/kevindazoo/aloud/kokoro/consumer
cat > Package.swift <<EOF
// swift-tools-version: 6.2
import PackageDescription

let package = Package(
    name: "consumer",
    platforms: [.macOS(.v15)],
    dependencies: [
        .package(url: "https://github.com/kevinxu-cmd/kokoro-coreml.git", revision: "$SDK_REV"),
    ],
    targets: [
        .executableTarget(
            name: "consumer",
            dependencies: [.product(name: "KokoroTTS", package: "kokoro-coreml")],
            swiftSettings: [.swiftLanguageMode(.v6)]),
    ]
)
EOF
cat > Sources/consumer/main.swift <<'EOF'
import KokoroTTS

let phonemizer = KokoroMisakiPhonemizer()
let result = try phonemizer.phonemize("Nobody really teaches you research, blorptastic as that is.")
print(result.phonemes)
print("dropped:", result.droppedTokens)
EOF
swift run 2>&1 | tail -3
```

Expected: a line of phonemes containing `blˌɔɹptˈæstɪk`, then `dropped: 0`.
This is the whole point of the plan in one command: the phonemizer, including its fallback, runs from `swift build` with no Xcode step.

- [ ] **Step 2: Record what plan 3 needs and remove the rehearsal**

```bash
echo "MISAKI_REV=$MISAKI_REV"
echo "SDK_REV=$SDK_REV"
cd /Users/kevindazoo/aloud/kokoro && rm -rf consumer
```

Hand both revisions to plan 3.
The dependency declaration plan 3 uses is the one in Step 1: `.package(url: "https://github.com/kevinxu-cmd/kokoro-coreml.git", revision: "SDK_REV")` with the product `KokoroTTS`.
The SDK's root manifest pins `MISAKI_REV`, so Aloud does not name MisakiSwift directly.
If the consumer's `swift run` fails in Swift 6 language mode on a concurrency diagnostic inside the SDK, that is a finding for plan 3, which wraps the SDK behind its own actor; record the diagnostic and rebuild the consumer with `.swiftLanguageMode(.v5)` to finish the check.

---

## Self-review against the spec

- "A fork of MisakiSwift in which that network is reimplemented on Accelerate, so MLX leaves the dependency tree": Tasks 3 to 7.
- "The fork of the SDK repoints that one line at your Misaki fork and changes nothing else": Task 8 changes the one line and also adds a root manifest, un-skips two tests and adds one. The root manifest is what lets Aloud pin the SDK by URL and revision as the spec requires, and the tests are what prove the fork works inside the SDK. The spec should be updated to name the root manifest when plan 3 lands.
- "The Accelerate network against the MLX one on a fixed word list": the golden comes from the PyTorch model rather than the MLX port, because MLX cannot run on this machine at all. Both ports derive from the PyTorch model, so this is the stronger reference. The spec should be updated to say so when plan 3 lands.
- "Pinned by exact revision": Task 7 and Task 8 produce the revisions; Task 9 rehearses the pin.
- No task references a type another task does not define. `Safetensors.bundledConfig` is introduced in Task 5 Step 1's note and lives in the Task 4 file.
