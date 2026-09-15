# Kokoro model bundle implementation plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** `make kokoro-bundle` builds the one archive of Kokoro models and voices that Aloud downloads on first use, byte-identical on any machine, proven loadable by the SDK, and attached to a release on the Aloud repo.

**Architecture:** A small library target, `KokoroBundle`, holds four pieces: the pinned list of input files with their checksums, a fetcher that fills a local inputs folder against those checksums, a builder that lays the files out the way the SDK's manifest expects and computes every digest with the SDK's own formula, and an Apple Archive writer and reader.
A thin executable, `kokoro-bundle`, strings them together; a test target builds a bundle from fixture files and loads it through the real SDK, and a gated test proves the digests match the ones upstream's own builder recorded for the same files.
The archive reader lives here so plan 3's app module can extract the same archives without a second implementation.

**Tech Stack:** Swift 6.2 strict concurrency, SwiftPM targets under `Tools/`, CryptoKit, AppleArchive, URLSession, Swift Testing, the `gh` CLI, the `KokoroTTS` product of the kokoro-coreml fork at revision `2932a26444b8deba2a6be6c0aa45c0424efaefe1`.

**Spec:** `docs/superpowers/specs/2026-09-13-kokoro-voices-design.md`, sections "What the SDK gives and requires", "The model bundle and the packaging tool" and "Testing".

This is plan 2 of 3.
Plan 1 produced the two forks; plan 3 integrates the app and pins the archive this plan publishes.

## Global Constraints

- macOS 26 only; Swift 6 language mode with strict concurrency in every new target (`swiftSettings: strict` as the other targets have).
- The SDK is consumed by URL and exact revision: `.package(url: "https://github.com/kevinxu-cmd/kokoro-coreml.git", revision: "2932a26444b8deba2a6be6c0aa45c0424efaefe1")`, product `KokoroTTS`. Never a version range: the SDK itself pins MisakiSwift by revision, and SwiftPM refuses a version-based dependency on a package that does that.
- The bundle layout is the SDK's: `KokoroRuntimeManifest.json` at the root, `coreml/<package>.mlpackage/`, `voices/<id>.bin`, `runtime/kokoro-vocab.json`, `runtime/hnsf_weights.json`.
- The manifest must decode with the SDK's internal `KokoroRuntimeManifest` type: `schema_version` 1, `hf_provenance_verified` true, `hf_download_manifest_sha256` a real 64-hex string (never null), `duration_token_sizes` exactly `[128]`, `buckets` `[15]`, `model_packages[].files` present, voice paths spelled `voices/<id>.bin`.
- Tree digests use the SDK's formula exactly: regular files only, sorted by relative path, and for each file the SHA-256 is fed `utf8(relativePath) 0x00 utf8(decimalByteCount) 0x00 utf8(lowercaseHexFileSHA256) 0x00`; `file_count` is the number of regular files and `bytes` their total.
- The bundle profile is `aloud`; `supported_languages` is `["en-US", "en-GB"]`; `sdk_commit` is the SDK fork revision above; `hf_repo_id` is `mattmireles/kokoro-coreml` and `hf_revision` is `9b6c8dbcf1209eedb554ca2fe98e947948061638`.
- Determinism: the same inputs give the same archive bytes on any machine. The archive's field key set is `TYP,PAT,DAT,MOD` (no times, no owners), file modes are normalised to 0644 and directories to 0755 before archiving, and the manifest is encoded with sorted keys and no timestamp.
- Nothing is downloaded at test time and nothing under `.build/` is committed. Every input is verified by size and SHA-256 before use; a mismatch is a failure, not a warning.
- Every commit passes `make check` and `make test`. `make check` lints the new tool folders too.
- No em dash in any file (plain dash). One sentence per line in Markdown. No co-author line in commits.
- Commit messages follow the repo's form: a sentence in the present tense, or a lower-case `docs:` prefix for documentation.
- `swift format lint --strict` runs in `make check`; run `swift format --in-place --recursive Sources Tests Tools/KokoroBundle Tools/kokoro-bundle` before committing if lint complains.

## Facts checked before writing this plan

- The SDK's `KokoroTTS.load(resources: .directory(root, compiledModelsDirectory:))` verifies the manifest, the voice and runtime-asset digests, and the presence of the four package directories, and compiles nothing. Package tree digests are verified on first synthesis. So a bundle whose packages are fake one-file directories loads, which is what the fixture test relies on.
- The hosted manifest upstream published for the same Hugging Face revision records tree digests for the four packages this plan uses. They are pinned below as `expectedTreeDigests`, and a gated test reproduces them from the downloaded inputs, which proves the Swift digest code matches upstream's JavaScript byte for byte.
- Apple Archive output built with the key set `TYP,PAT,DAT,MOD` was byte-identical across two source trees with different modification times on this machine; with the default key set it was not.
- `URLSession.shared.download(from:)` returns a temporary file that must be moved before the call returns to the caller's next await.
- The `gh` login `kevinxu-cmd` has push rights on `kevxuUmich/Aloud`, so `gh release create` and `gh release upload` work from this machine.
- The eleven Hugging Face files below were listed from the repository tree at revision `9b6c8dbcf1209eedb554ca2fe98e947948061638` on 2026-09-14; sizes and SHA-256 values come from the LFS metadata and from upstream's hosted manifest.

## File structure

- Create `Tools/KokoroBundle/PinnedInput.swift`: the `PinnedInput` value and `KokoroInputs`, the pinned list of 21 files and the four expected tree digests.
- Create `Tools/KokoroBundle/Digest.swift`: SHA-256 of a file, `FileDigest`, `PackageDigest` and the tree digest.
- Create `Tools/KokoroBundle/RuntimeManifest.swift`: the manifest as a `Codable` struct with the SDK's JSON keys and a stable encoding.
- Create `Tools/KokoroBundle/BundleBuilder.swift`: lays out a bundle from an inputs folder, writes the download manifest and the runtime manifest, normalises permissions.
- Create `Tools/KokoroBundle/AppleArchiveFile.swift`: `compress(directory:to:)` and `extract(archive:into:)`.
- Create `Tools/KokoroBundle/Fetcher.swift`: fills the inputs folder against the pinned list.
- Create `Tools/kokoro-bundle/main.swift`: the command.
- Create `Tests/KokoroBundleTests/DigestTests.swift`, `BundleBuilderTests.swift`, `AppleArchiveFileTests.swift`, `FetcherTests.swift`, `ParityTests.swift`, and `Tests/KokoroBundleTests/Fixtures/kokoro-vocab.json` and `hnsf_weights.json` (copies of the SDK's two runtime assets).
- Modify `Package.swift`: the SDK dependency, the two new targets, the test target, and a `KokoroBundle` library product.
- Modify `Makefile`: `kokoro-bundle` and `kokoro-release` targets, and the lint list in `check`.

Working directory: `/Users/kevindazoo/aloud`.
The SDK fork checkout at `/Users/kevindazoo/aloud/kokoro/kokoro-coreml` is useful for reading but nothing here depends on it: the SDK is resolved from GitHub by revision.

---

### Task 1: Package wiring and the digest code

**Files:**
- Modify: `Package.swift`
- Modify: `Makefile:38-40` (the `check` target's lint line)
- Create: `Tools/KokoroBundle/Digest.swift`
- Test: `Tests/KokoroBundleTests/DigestTests.swift`

**Interfaces:**
- Produces:

```swift
public enum Digest {
  static func sha256(ofFileAt url: URL) throws -> String     // lowercase hex
  static func sha256(of data: Data) -> String
  static func file(at url: URL, path: String) throws -> FileDigest
  static func package(at packageURL: URL, path: String) throws -> PackageDigest
}
public struct FileDigest: Codable, Sendable, Equatable { let path: String; let bytes: Int; let sha256: String }
public struct PackageDigest: Codable, Sendable, Equatable {
  let path: String; let treeSHA256: String; let fileCount: Int; let bytes: Int; let files: [FileDigest]
}
public enum DigestError: Error, Equatable { case unreadable(String), symlink(String) }
```

- [ ] **Step 1: Add the dependency and the targets to `Package.swift`**

Add to the `products` array, after the `Speech` product:

```swift
        // The bundle tool's library, a product so plan 3's Xcode target can link its
        // archive reader.
        .library(name: "KokoroBundle", targets: ["KokoroBundle"]),
```

Add to the `dependencies` array, after the KeyboardShortcuts entry:

```swift
        // The Kokoro SDK, Aloud's fork, pinned by exact revision. It pins its own
        // MisakiSwift fork by revision, and SwiftPM refuses a version range over a
        // package that does, so this stays a revision too.
        .package(
            url: "https://github.com/kevinxu-cmd/kokoro-coreml.git",
            revision: "2932a26444b8deba2a6be6c0aa45c0424efaefe1"),
```

Add to the `targets` array, before the first `.testTarget`:

```swift
        // The model bundle tool lives under Tools/ rather than Sources/: it is not part
        // of the app, it produces the archive the app downloads.
        .target(name: "KokoroBundle", path: "Tools/KokoroBundle", swiftSettings: strict),
        .executableTarget(
            name: "kokoro-bundle", dependencies: ["KokoroBundle"], path: "Tools/kokoro-bundle",
            swiftSettings: strict),
```

Add to the `targets` array, after the `SpeechTests` entry:

```swift
        .testTarget(
            name: "KokoroBundleTests",
            dependencies: ["KokoroBundle", .product(name: "KokoroTTS", package: "kokoro-coreml")],
            resources: [.copy("Fixtures")], swiftSettings: strict),
```

- [ ] **Step 2: Add the tool folders to the lint in `Makefile`**

Replace the `check` target's first line:

```makefile
	swift format lint --strict --recursive Sources Tests Package.swift
```

with:

```makefile
	swift format lint --strict --recursive Sources Tests Tools/KokoroBundle Tools/kokoro-bundle Package.swift
```

- [ ] **Step 3: Write the failing digest tests**

Create `Tests/KokoroBundleTests/DigestTests.swift`:

```swift
import CryptoKit
import Foundation
import Testing

@testable import KokoroBundle

@Suite struct DigestTests {
    func scratch() throws -> URL {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        return url
    }

    func hex(_ digest: SHA256.Digest) -> String { digest.map { String(format: "%02x", $0) }.joined() }

    /// The tree digest is a hash over a list of per-file hashes, not over the bytes: the
    /// SDK feeds path, size and file hash, each followed by a zero byte, in path order.
    @Test func packageDigestIsTheSDKFormula() throws {
        let root = try scratch()
        let package = root.appendingPathComponent("kokoro_duration_t128.mlpackage")
        let payload = package.appendingPathComponent("Data/com.apple.CoreML")
        try FileManager.default.createDirectory(at: payload, withIntermediateDirectories: true)
        let data = Data("duration-128".utf8)
        try data.write(to: payload.appendingPathComponent("model.mlmodel"))

        let d = try Digest.package(at: package, path: "coreml/kokoro_duration_t128.mlpackage")

        let fileHash = hex(SHA256.hash(data: data))
        var hasher = SHA256()
        hasher.update(data: Data("Data/com.apple.CoreML/model.mlmodel".utf8))
        hasher.update(data: Data([0]))
        hasher.update(data: Data(String(data.count).utf8))
        hasher.update(data: Data([0]))
        hasher.update(data: Data(fileHash.utf8))
        hasher.update(data: Data([0]))
        #expect(d.treeSHA256 == hex(hasher.finalize()))
        #expect(d.path == "coreml/kokoro_duration_t128.mlpackage")
        #expect(d.fileCount == 1)
        #expect(d.bytes == data.count)
        #expect(d.files == [FileDigest(path: "Data/com.apple.CoreML/model.mlmodel", bytes: data.count, sha256: fileHash)])
    }

    /// Files are taken in relative-path order however the file system lists them, and
    /// directories contribute nothing of their own.
    @Test func filesAreOrderedByRelativePath() throws {
        let root = try scratch()
        let package = root.appendingPathComponent("p.mlpackage")
        try FileManager.default.createDirectory(
            at: package.appendingPathComponent("Data/weights"), withIntermediateDirectories: true)
        try Data("z".utf8).write(to: package.appendingPathComponent("Manifest.json"))
        try Data("a".utf8).write(to: package.appendingPathComponent("Data/weights/weight.bin"))
        try Data("m".utf8).write(to: package.appendingPathComponent("Data/model.mlmodel"))

        let d = try Digest.package(at: package, path: "coreml/p.mlpackage")

        #expect(d.files.map(\.path) == ["Data/model.mlmodel", "Data/weights/weight.bin", "Manifest.json"])
        #expect(d.fileCount == 3)
        #expect(d.bytes == 3)
    }

    /// A symlink inside a package is refused, as the SDK refuses it at load.
    @Test func symlinksAreRefused() throws {
        let root = try scratch()
        let package = root.appendingPathComponent("p.mlpackage")
        try FileManager.default.createDirectory(at: package, withIntermediateDirectories: true)
        try Data("m".utf8).write(to: package.appendingPathComponent("model.mlmodel"))
        try FileManager.default.createSymbolicLink(
            at: package.appendingPathComponent("link"), withDestinationURL: package.appendingPathComponent("model.mlmodel"))

        #expect(throws: DigestError.self) { try Digest.package(at: package, path: "coreml/p.mlpackage") }
    }

    /// A file digest is the streamed SHA-256 of the bytes and the byte count.
    @Test func fileDigestStreamsTheWholeFile() throws {
        let root = try scratch()
        let url = root.appendingPathComponent("v.bin")
        let data = Data((0..<3_000_000).map { UInt8(truncatingIfNeeded: $0) })
        try data.write(to: url)

        let d = try Digest.file(at: url, path: "voices/v.bin")

        #expect(d == FileDigest(path: "voices/v.bin", bytes: data.count, sha256: hex(SHA256.hash(data: data))))
    }
}
```

- [ ] **Step 4: Run to see them fail**

```bash
cd /Users/kevindazoo/aloud
swift build --target KokoroBundleTests 2>&1 | grep -E "error:" | head -3
```

Expected: errors that `Digest` and `FileDigest` do not exist (the target itself needs at least one source file, which the next step creates).
The first build resolves and compiles the SDK; allow several minutes.

- [ ] **Step 5: Implement the digest code**

Create `Tools/KokoroBundle/Digest.swift`:

```swift
import CryptoKit
import Foundation

/// One file's place in a bundle: its path relative to the bundle root, its size and its
/// SHA-256. The shape the SDK's manifest uses for voices, runtime assets and the files
/// inside a package.
public struct FileDigest: Codable, Sendable, Equatable {
    public let path: String
    public let bytes: Int
    public let sha256: String
    public init(path: String, bytes: Int, sha256: String) {
        self.path = path
        self.bytes = bytes
        self.sha256 = sha256
    }
}

/// One `.mlpackage` in the manifest: a digest over its files, taken the SDK's way.
public struct PackageDigest: Codable, Sendable, Equatable {
    public let path: String
    public let treeSHA256: String
    public let fileCount: Int
    public let bytes: Int
    public let files: [FileDigest]
    enum CodingKeys: String, CodingKey {
        case path
        case treeSHA256 = "tree_sha256"
        case fileCount = "file_count"
        case bytes
        case files
    }
}

public enum DigestError: Error, Equatable {
    case unreadable(String)
    case symlink(String)
}

public enum Digest {
    /// Lowercase hex SHA-256 of a file, streamed so a 67 MB weight file is never held whole.
    public static func sha256(ofFileAt url: URL) throws -> String {
        let handle = try FileHandle(forReadingFrom: url)
        defer { try? handle.close() }
        var hasher = SHA256()
        while true {
            let chunk = try handle.read(upToCount: 1 << 20) ?? Data()
            if chunk.isEmpty { break }
            hasher.update(data: chunk)
        }
        return hex(hasher.finalize())
    }

    public static func sha256(of data: Data) -> String { hex(SHA256.hash(data: data)) }

    public static func file(at url: URL, path: String) throws -> FileDigest {
        let bytes = try url.resourceValues(forKeys: [.fileSizeKey]).fileSize ?? 0
        return FileDigest(path: path, bytes: bytes, sha256: try sha256(ofFileAt: url))
    }

    /// The SDK's tree digest for a package. Regular files only, in relative-path order,
    /// and for each one the path, the decimal size and the file's hex SHA-256, each
    /// followed by a zero byte. A symlink anywhere inside is refused, as the SDK refuses
    /// it at load.
    public static func package(at packageURL: URL, path: String) throws -> PackageDigest {
        let root = packageURL.standardizedFileURL.path
        let keys: Set<URLResourceKey> = [.isRegularFileKey, .isSymbolicLinkKey]
        guard
            let enumerator = FileManager.default.enumerator(
                at: packageURL, includingPropertiesForKeys: Array(keys), options: [])
        else { throw DigestError.unreadable(packageURL.path) }
        var entries: [(relativePath: String, url: URL)] = []
        for case let url as URL in enumerator {
            let values = try url.resourceValues(forKeys: keys)
            if values.isSymbolicLink == true { throw DigestError.symlink(url.path) }
            guard values.isRegularFile == true else { continue }
            let full = url.standardizedFileURL.path
            entries.append((String(full.dropFirst(root.count + 1)), url))
        }
        entries.sort { $0.relativePath < $1.relativePath }
        var hasher = SHA256()
        var files: [FileDigest] = []
        var total = 0
        for entry in entries {
            let digest = try file(at: entry.url, path: entry.relativePath)
            hasher.update(data: Data(digest.path.utf8))
            hasher.update(data: Data([0]))
            hasher.update(data: Data(String(digest.bytes).utf8))
            hasher.update(data: Data([0]))
            hasher.update(data: Data(digest.sha256.utf8))
            hasher.update(data: Data([0]))
            files.append(digest)
            total += digest.bytes
        }
        return PackageDigest(
            path: path, treeSHA256: hex(hasher.finalize()), fileCount: files.count, bytes: total,
            files: files)
    }

    static func hex<S: Sequence>(_ bytes: S) -> String where S.Element == UInt8 {
        bytes.map { String(format: "%02x", $0) }.joined()
    }
}
```

- [ ] **Step 6: Run the digest tests**

```bash
swift test --filter DigestTests 2>&1 | grep -E "Test .* (passed|failed)|error:" | tail -6
```

Expected: four passes.

- [ ] **Step 7: Check and commit**

```bash
make check 2>&1 | tail -3
git add Package.swift Package.resolved Makefile Tools/KokoroBundle/Digest.swift Tests/KokoroBundleTests/DigestTests.swift
git commit -m "The bundle tool's digest code matches the SDK's tree formula"
```

`Package.resolved` now records the SDK fork and its MisakiSwift fork; commit it with the manifest.

---

### Task 2: The manifest, the builder, and a bundle the SDK loads

**Files:**
- Create: `Tools/KokoroBundle/RuntimeManifest.swift`
- Create: `Tools/KokoroBundle/BundleBuilder.swift`
- Create: `Tests/KokoroBundleTests/Fixtures/kokoro-vocab.json`
- Create: `Tests/KokoroBundleTests/Fixtures/hnsf_weights.json`
- Test: `Tests/KokoroBundleTests/BundleBuilderTests.swift`

**Interfaces:**
- Consumes: `Digest`, `FileDigest`, `PackageDigest` from Task 1.
- Produces:

```swift
public struct RuntimeManifest: Codable, Sendable, Equatable {
  static let fileName = "KokoroRuntimeManifest.json"
  func encoded() throws -> Data          // sorted keys, pretty printed, trailing newline
  // fields listed in the implementation below
}
public struct Provenance: Sendable {
  let sdkCommit: String; let hfRepo: String; let hfRevision: String; let inputs: [PinnedRecord]
  func downloadManifest() throws -> Data
}
public struct PinnedRecord: Codable, Sendable, Equatable { let path: String; let url: String; let bytes: Int; let sha256: String }
public struct BundleBuilder: Sendable {
  init(inputs: URL, packages: [String], voices: [String])
  static let downloadManifestName = "AloudDownloadManifest.json"
  @discardableResult func build(into root: URL, provenance: Provenance) throws -> RuntimeManifest
}
public enum BuildError: Error, Equatable { case missingInput(String), badVoiceID(String) }
```

The inputs folder mirrors the source paths: `coreml/<package>.mlpackage/...`, `kokoro.js/voices/<id>.bin`, `runtime/kokoro-vocab.json`, `runtime/hnsf_weights.json`.
The builder maps them to the SDK layout.

- [ ] **Step 1: Copy the two runtime assets into the test fixtures**

```bash
cd /Users/kevindazoo/aloud
mkdir -p Tests/KokoroBundleTests/Fixtures
cp kokoro/kokoro-coreml/swift-tts/Sources/KokoroTTS/Resources/KokoroRuntime/kokoro-vocab.json Tests/KokoroBundleTests/Fixtures/
cp kokoro/kokoro-coreml/swift-tts/Sources/KokoroTTS/Resources/KokoroRuntime/hnsf_weights.json Tests/KokoroBundleTests/Fixtures/
shasum -a 256 Tests/KokoroBundleTests/Fixtures/*
```

Expected: `353ca94410fde4575cb091a0ba32b8e99077fde4f38fded506f4f041d22571a3` for the vocab and `de73b717732da77b31736f67a108d35c478ab116b0a188e9787019b0408c0226` for the weights.
If the SDK checkout is not on this machine, fetch the two files from `https://raw.githubusercontent.com/kevinxu-cmd/kokoro-coreml/2932a26444b8deba2a6be6c0aa45c0424efaefe1/swift-tts/Sources/KokoroTTS/Resources/KokoroRuntime/` and check the same two hashes.

- [ ] **Step 2: Write the failing builder tests**

Create `Tests/KokoroBundleTests/BundleBuilderTests.swift`:

```swift
import Foundation
import KokoroTTS
import Testing

@testable import KokoroBundle

@Suite struct BundleBuilderTests {
    static let voices = ["af_bella", "af_sarah", "am_michael", "am_fenrir", "bf_emma", "bm_george", "bm_fable"]
    static let packages = [
        "kokoro_duration_t128", "kokoro_f0ntrain_t600", "kokoro_decoder_pre_15s", "kokoro_decoder_har_post_15s",
    ]

    func scratch() throws -> URL {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        return url
    }

    /// An inputs folder in the source layout: four fake one-file packages, seven voices
    /// of one zero row each (the SDK wants a multiple of 1024 bytes), and the two real
    /// runtime assets.
    func makeInputs() throws -> URL {
        let inputs = try scratch()
        let fm = FileManager.default
        for (i, name) in Self.packages.enumerated() {
            let payload = inputs.appendingPathComponent("coreml/\(name).mlpackage/Data/com.apple.CoreML")
            try fm.createDirectory(at: payload, withIntermediateDirectories: true)
            try Data("model-\(i)".utf8).write(to: payload.appendingPathComponent("model.mlmodel"))
        }
        try fm.createDirectory(at: inputs.appendingPathComponent("kokoro.js/voices"), withIntermediateDirectories: true)
        for (i, id) in Self.voices.enumerated() {
            var row = Data(count: 256 * 4)
            row[0] = UInt8(i + 1)
            try row.write(to: inputs.appendingPathComponent("kokoro.js/voices/\(id).bin"))
        }
        try fm.createDirectory(at: inputs.appendingPathComponent("runtime"), withIntermediateDirectories: true)
        for name in ["kokoro-vocab.json", "hnsf_weights.json"] {
            let src = try #require(Bundle.module.url(forResource: name, withExtension: nil, subdirectory: "Fixtures"))
            try fm.copyItem(at: src, to: inputs.appendingPathComponent("runtime/\(name)"))
        }
        return inputs
    }

    var provenance: Provenance {
        Provenance(
            sdkCommit: "2932a26444b8deba2a6be6c0aa45c0424efaefe1", hfRepo: "mattmireles/kokoro-coreml",
            hfRevision: "9b6c8dbcf1209eedb554ca2fe98e947948061638",
            inputs: [PinnedRecord(path: "coreml/x", url: "https://example.invalid/x", bytes: 1, sha256: String(repeating: "a", count: 64))])
    }

    func build() throws -> (root: URL, manifest: RuntimeManifest) {
        let root = try scratch().appendingPathComponent("kokoro-1")
        let m = try BundleBuilder(inputs: try makeInputs(), packages: Self.packages, voices: Self.voices)
            .build(into: root, provenance: provenance)
        return (root, m)
    }

    /// The whole point: what the builder writes, the SDK loads.
    @Test func theSDKLoadsWhatTheBuilderWrites() async throws {
        let (root, _) = try build()
        let cache = try scratch()
        _ = try await KokoroTTS.load(resources: .directory(root, compiledModelsDirectory: cache))
    }

    /// A byte changed after the build is caught by the SDK's digest check, which is the
    /// check the bundle's checksums exist to feed.
    @Test func aTamperedVoiceIsRefusedBySDK() async throws {
        let (root, _) = try build()
        let voice = root.appendingPathComponent("voices/af_bella.bin")
        var data = try Data(contentsOf: voice)
        data[5] ^= 0xFF
        try data.write(to: voice)
        let cache = try scratch()
        await #expect(throws: KokoroError.badHash(path: "voices/af_bella.bin")) {
            _ = try await KokoroTTS.load(resources: .directory(root, compiledModelsDirectory: cache))
        }
    }

    @Test func theManifestSaysWhatTheSDKRequires() throws {
        let (root, m) = try build()
        #expect(m.schemaVersion == 1)
        #expect(m.hfProvenanceVerified)
        #expect(m.durationTokenSizes == [128])
        #expect(m.buckets == [15])
        #expect(m.bundleProfile == "aloud")
        #expect(m.supportedLanguages == ["en-US", "en-GB"])
        #expect(m.sdkCommit == "2932a26444b8deba2a6be6c0aa45c0424efaefe1")
        #expect(m.modelPackages.map(\.path) == Self.packages.map { "coreml/\($0).mlpackage" })
        #expect(m.voices.map(\.path) == Self.voices.sorted().map { "voices/\($0).bin" })
        #expect(m.voices.allSatisfy { $0.bytes == 1024 })
        #expect(m.runtimeAssets.vocab.path == "runtime/kokoro-vocab.json")
        #expect(m.runtimeAssets.vocab.sha256 == "353ca94410fde4575cb091a0ba32b8e99077fde4f38fded506f4f041d22571a3")
        #expect(m.runtimeAssets.hnsfWeights.sha256 == "de73b717732da77b31736f67a108d35c478ab116b0a188e9787019b0408c0226")
        let download = try Data(contentsOf: root.appendingPathComponent(BundleBuilder.downloadManifestName))
        #expect(m.hfDownloadManifestSHA256 == Digest.sha256(of: download))
        let written = try Data(contentsOf: root.appendingPathComponent(RuntimeManifest.fileName))
        #expect(written == (try m.encoded()))
    }

    /// The manifest's JSON keys are the SDK's, spelled its way.
    @Test func theJSONKeysAreTheSDKs() throws {
        let (_, m) = try build()
        let object = try #require(JSONSerialization.jsonObject(with: try m.encoded()) as? [String: Any])
        #expect(
            Set(object.keys) == [
                "schema_version", "sdk_commit", "hf_repo_id", "hf_revision", "hf_provenance_verified",
                "hf_download_manifest_sha256", "minimum_platforms", "supported_languages", "bundle_profile",
                "buckets", "duration_token_sizes", "model_packages", "voices", "runtime_assets",
            ])
        let package = try #require((object["model_packages"] as? [[String: Any]])?.first)
        #expect(Set(package.keys) == ["path", "tree_sha256", "file_count", "bytes", "files"])
        let assets = try #require(object["runtime_assets"] as? [String: Any])
        #expect(Set(assets.keys) == ["vocab", "hnsf_weights"])
    }

    /// Two builds from the same inputs write the same bytes: no timestamp, sorted keys.
    @Test func twoBuildsAreIdentical() throws {
        let inputs = try makeInputs()
        let a = try scratch().appendingPathComponent("a")
        let b = try scratch().appendingPathComponent("b")
        let builder = BundleBuilder(inputs: inputs, packages: Self.packages, voices: Self.voices)
        try builder.build(into: a, provenance: provenance)
        try builder.build(into: b, provenance: provenance)
        #expect(
            try Data(contentsOf: a.appendingPathComponent(RuntimeManifest.fileName))
                == Data(contentsOf: b.appendingPathComponent(RuntimeManifest.fileName)))
    }

    @Test func permissionsAreNormalised() throws {
        let (root, _) = try build()
        let file = root.appendingPathComponent("voices/af_bella.bin")
        let dir = root.appendingPathComponent("coreml")
        #expect(try FileManager.default.attributesOfItem(atPath: file.path)[.posixPermissions] as? Int == 0o644)
        #expect(try FileManager.default.attributesOfItem(atPath: dir.path)[.posixPermissions] as? Int == 0o755)
    }

    @Test func aMissingInputIsNamed() throws {
        let inputs = try makeInputs()
        try FileManager.default.removeItem(at: inputs.appendingPathComponent("kokoro.js/voices/bm_fable.bin"))
        let root = try scratch().appendingPathComponent("r")
        #expect(throws: BuildError.missingInput("kokoro.js/voices/bm_fable.bin")) {
            try BundleBuilder(inputs: inputs, packages: Self.packages, voices: Self.voices)
                .build(into: root, provenance: provenance)
        }
    }

    @Test func aVoiceIDThatIsNotAVoiceIDIsRefused() throws {
        let root = try scratch().appendingPathComponent("r")
        #expect(throws: BuildError.badVoiceID("../etc")) {
            try BundleBuilder(inputs: try makeInputs(), packages: Self.packages, voices: ["../etc"])
                .build(into: root, provenance: provenance)
        }
    }
}
```

- [ ] **Step 3: Run to see them fail**

```bash
swift test --filter BundleBuilderTests 2>&1 | grep -E "error:" | head -3
```

Expected: `cannot find 'BundleBuilder' in scope` or similar.

- [ ] **Step 4: Implement the manifest**

Create `Tools/KokoroBundle/RuntimeManifest.swift`:

```swift
import Foundation

/// The SDK's `KokoroRuntimeManifest.json`, as the SDK's internal decoder reads it. The
/// SDK does not expose its type, so this is the same shape spelled out here, with the
/// JSON keys copied from it.
public struct RuntimeManifest: Codable, Sendable, Equatable {
    public static let fileName = "KokoroRuntimeManifest.json"

    public var schemaVersion = 1
    public var sdkCommit: String
    public var hfRepoID: String
    public var hfRevision: String
    public var hfProvenanceVerified = true
    public var hfDownloadManifestSHA256: String
    public var minimumPlatforms: [String: String]
    public var supportedLanguages: [String]
    public var bundleProfile: String
    public var buckets: [Int]
    public var durationTokenSizes: [Int]
    public var modelPackages: [PackageDigest]
    public var voices: [FileDigest]
    public var runtimeAssets: RuntimeAssets

    public struct RuntimeAssets: Codable, Sendable, Equatable {
        public var vocab: FileDigest
        public var hnsfWeights: FileDigest
        public init(vocab: FileDigest, hnsfWeights: FileDigest) {
            self.vocab = vocab
            self.hnsfWeights = hnsfWeights
        }
        enum CodingKeys: String, CodingKey {
            case vocab
            case hnsfWeights = "hnsf_weights"
        }
    }

    enum CodingKeys: String, CodingKey {
        case schemaVersion = "schema_version"
        case sdkCommit = "sdk_commit"
        case hfRepoID = "hf_repo_id"
        case hfRevision = "hf_revision"
        case hfProvenanceVerified = "hf_provenance_verified"
        case hfDownloadManifestSHA256 = "hf_download_manifest_sha256"
        case minimumPlatforms = "minimum_platforms"
        case supportedLanguages = "supported_languages"
        case bundleProfile = "bundle_profile"
        case buckets
        case durationTokenSizes = "duration_token_sizes"
        case modelPackages = "model_packages"
        case voices
        case runtimeAssets = "runtime_assets"
    }

    public init(
        sdkCommit: String, hfRepoID: String, hfRevision: String, hfDownloadManifestSHA256: String,
        minimumPlatforms: [String: String], supportedLanguages: [String], bundleProfile: String,
        buckets: [Int], durationTokenSizes: [Int], modelPackages: [PackageDigest], voices: [FileDigest],
        runtimeAssets: RuntimeAssets
    ) {
        self.sdkCommit = sdkCommit
        self.hfRepoID = hfRepoID
        self.hfRevision = hfRevision
        self.hfDownloadManifestSHA256 = hfDownloadManifestSHA256
        self.minimumPlatforms = minimumPlatforms
        self.supportedLanguages = supportedLanguages
        self.bundleProfile = bundleProfile
        self.buckets = buckets
        self.durationTokenSizes = durationTokenSizes
        self.modelPackages = modelPackages
        self.voices = voices
        self.runtimeAssets = runtimeAssets
    }

    /// Stable bytes: sorted keys, pretty printed, slashes unescaped, one trailing newline.
    /// The same manifest always encodes to the same bytes, which the archive's checksum
    /// depends on.
    public func encoded() throws -> Data {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]
        return try encoder.encode(self) + Data("\n".utf8)
    }
}
```

- [ ] **Step 5: Implement the builder**

Create `Tools/KokoroBundle/BundleBuilder.swift`:

```swift
import Foundation

/// Where one input came from and what it hashed to, recorded in the bundle so the
/// manifest's provenance digest is over something real.
public struct PinnedRecord: Codable, Sendable, Equatable {
    public let path: String
    public let url: String
    public let bytes: Int
    public let sha256: String
    public init(path: String, url: String, bytes: Int, sha256: String) {
        self.path = path
        self.url = url
        self.bytes = bytes
        self.sha256 = sha256
    }
}

/// What the manifest says about where the models came from.
public struct Provenance: Sendable {
    public let sdkCommit: String
    public let hfRepo: String
    public let hfRevision: String
    public let inputs: [PinnedRecord]
    public init(sdkCommit: String, hfRepo: String, hfRevision: String, inputs: [PinnedRecord]) {
        self.sdkCommit = sdkCommit
        self.hfRepo = hfRepo
        self.hfRevision = hfRevision
        self.inputs = inputs
    }

    struct DownloadManifest: Codable {
        let schemaVersion: Int
        let repoID: String
        let revision: String
        let files: [PinnedRecord]
        enum CodingKeys: String, CodingKey {
            case schemaVersion = "schema_version"
            case repoID = "repo_id"
            case revision
            case files
        }
    }

    /// The pinned inputs as one stable JSON document. Its SHA-256 is the manifest's
    /// `hf_download_manifest_sha256`, the way upstream's builder hashes the download
    /// manifest its Python fetcher wrote.
    public func downloadManifest() throws -> Data {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]
        let document = DownloadManifest(
            schemaVersion: 1, repoID: hfRepo, revision: hfRevision,
            files: inputs.sorted { $0.path < $1.path })
        return try encoder.encode(document) + Data("\n".utf8)
    }
}

public enum BuildError: Error, Equatable {
    case missingInput(String)
    case badVoiceID(String)
}

/// Lays the inputs out the way the SDK reads them and writes the manifest over them.
public struct BundleBuilder: Sendable {
    public static let downloadManifestName = "AloudDownloadManifest.json"
    static let runtimeAssetNames = ["kokoro-vocab.json", "hnsf_weights.json"]

    public let inputs: URL
    public let packages: [String]
    public let voices: [String]

    public init(inputs: URL, packages: [String], voices: [String]) {
        self.inputs = inputs
        self.packages = packages
        self.voices = voices
    }

    /// Builds the bundle folder at `root`, replacing one already there, and returns the
    /// manifest it wrote.
    @discardableResult
    public func build(into root: URL, provenance: Provenance) throws -> RuntimeManifest {
        let fm = FileManager.default
        try? fm.removeItem(at: root)
        for folder in ["coreml", "voices", "runtime"] {
            try fm.createDirectory(at: root.appendingPathComponent(folder), withIntermediateDirectories: true)
        }
        var modelPackages: [PackageDigest] = []
        for name in packages {
            let relative = "coreml/\(name).mlpackage"
            let destination = try copy(relative, to: root.appendingPathComponent(relative))
            modelPackages.append(try Digest.package(at: destination, path: relative))
        }
        var voiceDigests: [FileDigest] = []
        for id in voices.sorted() {
            guard Self.isVoiceID(id) else { throw BuildError.badVoiceID(id) }
            let destination = try copy("kokoro.js/voices/\(id).bin", to: root.appendingPathComponent("voices/\(id).bin"))
            voiceDigests.append(try Digest.file(at: destination, path: "voices/\(id).bin"))
        }
        var assets: [String: FileDigest] = [:]
        for name in Self.runtimeAssetNames {
            let relative = "runtime/\(name)"
            let destination = try copy(relative, to: root.appendingPathComponent(relative))
            assets[name] = try Digest.file(at: destination, path: relative)
        }
        let download = try provenance.downloadManifest()
        try download.write(to: root.appendingPathComponent(Self.downloadManifestName))
        let manifest = RuntimeManifest(
            sdkCommit: provenance.sdkCommit, hfRepoID: provenance.hfRepo, hfRevision: provenance.hfRevision,
            hfDownloadManifestSHA256: Digest.sha256(of: download),
            minimumPlatforms: ["macOS": "15.0", "iOS": "18.0"], supportedLanguages: ["en-US", "en-GB"],
            bundleProfile: "aloud", buckets: [15], durationTokenSizes: [128], modelPackages: modelPackages,
            voices: voiceDigests,
            runtimeAssets: .init(vocab: assets["kokoro-vocab.json"]!, hnsfWeights: assets["hnsf_weights.json"]!))
        try manifest.encoded().write(to: root.appendingPathComponent(RuntimeManifest.fileName))
        try Self.normalisePermissions(under: root)
        return manifest
    }

    private func copy(_ relative: String, to destination: URL) throws -> URL {
        let source = inputs.appendingPathComponent(relative)
        guard FileManager.default.fileExists(atPath: source.path) else { throw BuildError.missingInput(relative) }
        try FileManager.default.createDirectory(
            at: destination.deletingLastPathComponent(), withIntermediateDirectories: true)
        try FileManager.default.copyItem(at: source, to: destination)
        return destination
    }

    /// A Kokoro voice id is a language letter, a gender letter, an underscore and a name:
    /// `af_bella`. Anything else is refused before it can become a path.
    static func isVoiceID(_ id: String) -> Bool {
        id.wholeMatch(of: /[ab][fm]_[a-z]+/) != nil
    }

    /// Files 0644 and directories 0755, so the archive's mode fields do not depend on the
    /// umask of the machine that built it.
    static func normalisePermissions(under root: URL) throws {
        let keys: Set<URLResourceKey> = [.isDirectoryKey]
        guard
            let enumerator = FileManager.default.enumerator(
                at: root, includingPropertiesForKeys: Array(keys), options: [])
        else { return }
        var urls = [root]
        for case let url as URL in enumerator { urls.append(url) }
        for url in urls {
            let isDirectory = try url.resourceValues(forKeys: keys).isDirectory == true
            try FileManager.default.setAttributes(
                [.posixPermissions: isDirectory ? 0o755 : 0o644], ofItemAtPath: url.path)
        }
    }
}
```

- [ ] **Step 6: Run the builder tests**

```bash
swift test --filter BundleBuilderTests 2>&1 | grep -E "Test .* (passed|failed)|error:|Expectation failed" | tail -12
```

Expected: eight passes.
If `theSDKLoadsWhatTheBuilderWrites` fails with `missingModel("kokoro_duration_t128.mlpackage")`, the SDK's `discoverDurationChoices` did not see the package directory: check the inputs helper wrote `coreml/<name>.mlpackage/Data/com.apple.CoreML/model.mlmodel` and the builder copied the directory whole.
If it fails with a `DecodingError`, a manifest key is misspelled; compare `CodingKeys` against the list in `theJSONKeysAreTheSDKs`.

- [ ] **Step 7: Check and commit**

```bash
make check 2>&1 | tail -3
git add Tools/KokoroBundle/RuntimeManifest.swift Tools/KokoroBundle/BundleBuilder.swift Tests/KokoroBundleTests
git commit -m "The bundle builder writes a layout the SDK loads, with its manifest and digests"
```

---

### Task 3: The archive writer and reader

**Files:**
- Create: `Tools/KokoroBundle/AppleArchiveFile.swift`
- Test: `Tests/KokoroBundleTests/AppleArchiveFileTests.swift`

**Interfaces:**
- Produces:

```swift
public enum AppleArchiveFile {
  static func compress(directory: URL, to archive: URL) throws
  static func extract(archive: URL, into directory: URL) throws
}
public enum ArchiveError: Error, Equatable { case cannotOpen(String), cannotWrite(String), cannotRead(String) }
```

The key set `TYP,PAT,DAT,MOD` is what makes two builds identical: entry type, path, data and mode, and none of the times or owners the default set carries.
Plan 3's app extracts with the same `extract`.

- [ ] **Step 1: Write the failing tests**

Create `Tests/KokoroBundleTests/AppleArchiveFileTests.swift`:

```swift
import CryptoKit
import Foundation
import Testing

@testable import KokoroBundle

@Suite struct AppleArchiveFileTests {
    func scratch() throws -> URL {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        return url
    }

    /// A tree with a nested package, a voice and a manifest, as a bundle has.
    func makeTree(in root: URL, stamp: Date) throws {
        let fm = FileManager.default
        try fm.createDirectory(at: root.appendingPathComponent("coreml/p.mlpackage/Data"), withIntermediateDirectories: true)
        try fm.createDirectory(at: root.appendingPathComponent("voices"), withIntermediateDirectories: true)
        try Data((0..<200_000).map { UInt8(truncatingIfNeeded: $0 % 251) })
            .write(to: root.appendingPathComponent("coreml/p.mlpackage/Data/weight.bin"))
        try Data(count: 1024).write(to: root.appendingPathComponent("voices/af_bella.bin"))
        try Data("{}\n".utf8).write(to: root.appendingPathComponent("KokoroRuntimeManifest.json"))
        try BundleBuilder.normalisePermissions(under: root)
        for path in ["KokoroRuntimeManifest.json", "voices/af_bella.bin"] {
            try fm.setAttributes([.modificationDate: stamp], ofItemAtPath: root.appendingPathComponent(path).path)
        }
    }

    @Test func aTreeSurvivesTheRoundTrip() throws {
        let src = try scratch()
        try makeTree(in: src, stamp: Date())
        let archive = try scratch().appendingPathComponent("t.aar")
        let dst = try scratch().appendingPathComponent("out")

        try AppleArchiveFile.compress(directory: src, to: archive)
        try AppleArchiveFile.extract(archive: archive, into: dst)

        for path in ["coreml/p.mlpackage/Data/weight.bin", "voices/af_bella.bin", "KokoroRuntimeManifest.json"] {
            #expect(
                try Data(contentsOf: dst.appendingPathComponent(path)) == Data(contentsOf: src.appendingPathComponent(path)),
                path)
        }
        #expect(
            try FileManager.default.attributesOfItem(atPath: dst.appendingPathComponent("voices/af_bella.bin").path)[
                .posixPermissions] as? Int == 0o644)
    }

    /// The same files archived on two days, or two machines, are the same bytes: the
    /// archive carries no times and no owners.
    @Test func twoArchivesOfTheSameTreeAreIdentical() throws {
        let a = try scratch()
        let b = try scratch()
        try makeTree(in: a, stamp: Date(timeIntervalSince1970: 0))
        try makeTree(in: b, stamp: Date())
        let archiveA = try scratch().appendingPathComponent("a.aar")
        let archiveB = try scratch().appendingPathComponent("b.aar")

        try AppleArchiveFile.compress(directory: a, to: archiveA)
        try AppleArchiveFile.compress(directory: b, to: archiveB)

        #expect(try Data(contentsOf: archiveA) == Data(contentsOf: archiveB))
    }

    @Test func aFileThatIsNotAnArchiveIsRefused() throws {
        let notArchive = try scratch().appendingPathComponent("x.aar")
        try Data("not an archive".utf8).write(to: notArchive)
        let dst = try scratch().appendingPathComponent("out")
        #expect(throws: (any Error).self) { try AppleArchiveFile.extract(archive: notArchive, into: dst) }
    }
}
```

- [ ] **Step 2: Run to see them fail**

```bash
swift test --filter AppleArchiveFileTests 2>&1 | grep -E "error:" | head -3
```

Expected: `cannot find 'AppleArchiveFile' in scope`.

- [ ] **Step 3: Implement the archive code**

Create `Tools/KokoroBundle/AppleArchiveFile.swift`:

```swift
import AppleArchive
import Foundation
import System

public enum ArchiveError: Error, Equatable {
    case cannotOpen(String)
    case cannotWrite(String)
    case cannotRead(String)
}

/// One Apple Archive of a directory, LZFSE compressed, the format the model bundle
/// ships in. The field key set is `TYP,PAT,DAT,MOD`: type, path, data and mode, and
/// none of the times or owners the default set carries, so the same tree gives the same
/// bytes on any machine.
public enum AppleArchiveFile {
    static let keySet = "TYP,PAT,DAT,MOD"

    public static func compress(directory: URL, to archive: URL) throws {
        guard
            let file = ArchiveByteStream.fileStream(
                path: FilePath(archive.path), mode: .writeOnly, options: [.create, .truncate],
                permissions: FilePermissions(rawValue: 0o644))
        else { throw ArchiveError.cannotWrite(archive.path) }
        defer { try? file.close() }
        guard let compression = ArchiveByteStream.compressionStream(using: .lzfse, writingTo: file) else {
            throw ArchiveError.cannotWrite(archive.path)
        }
        defer { try? compression.close() }
        guard let encoder = ArchiveStream.encodeStream(writingTo: compression) else {
            throw ArchiveError.cannotWrite(archive.path)
        }
        defer { try? encoder.close() }
        guard let keys = ArchiveHeader.FieldKeySet(keySet) else { throw ArchiveError.cannotWrite(keySet) }
        try encoder.writeDirectoryContents(archiveFrom: FilePath(directory.path), keySet: keys)
    }

    /// Extracts the archive's tree into `directory`, creating it. The archive is trusted
    /// only after its checksum matched, which is the caller's job.
    public static func extract(archive: URL, into directory: URL) throws {
        guard
            let file = ArchiveByteStream.fileStream(
                path: FilePath(archive.path), mode: .readOnly, options: [],
                permissions: FilePermissions(rawValue: 0o644))
        else { throw ArchiveError.cannotOpen(archive.path) }
        defer { try? file.close() }
        guard let decompression = ArchiveByteStream.decompressionStream(readingFrom: file) else {
            throw ArchiveError.cannotRead(archive.path)
        }
        defer { try? decompression.close() }
        guard let decoder = ArchiveStream.decodeStream(readingFrom: decompression) else {
            throw ArchiveError.cannotRead(archive.path)
        }
        defer { try? decoder.close() }
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        guard
            let extractor = ArchiveStream.extractStream(
                extractingTo: FilePath(directory.path), flags: [.ignoreOperationNotPermitted])
        else { throw ArchiveError.cannotWrite(directory.path) }
        defer { try? extractor.close() }
        _ = try ArchiveStream.process(readingFrom: decoder, writingTo: extractor)
    }
}
```

- [ ] **Step 4: Run the archive tests**

```bash
swift test --filter AppleArchiveFileTests 2>&1 | grep -E "Test .* (passed|failed)|error:" | tail -5
```

Expected: three passes.
If `aFileThatIsNotAnArchiveIsRefused` does not throw, `decompressionStream` accepted the header; in that case check that `process` throws instead, and if neither does, read one header with `decoder.readHeader()` and throw `ArchiveError.cannotRead` when it returns nil.

- [ ] **Step 5: Check and commit**

```bash
make check 2>&1 | tail -3
git add Tools/KokoroBundle/AppleArchiveFile.swift Tests/KokoroBundleTests/AppleArchiveFileTests.swift
git commit -m "The bundle is one Apple Archive, and the same tree always gives the same bytes"
```

---

### Task 4: The pinned inputs and the fetcher

**Files:**
- Create: `Tools/KokoroBundle/PinnedInput.swift`
- Create: `Tools/KokoroBundle/Fetcher.swift`
- Test: `Tests/KokoroBundleTests/FetcherTests.swift`

**Interfaces:**
- Produces:

```swift
public struct PinnedInput: Sendable, Hashable { let path: String; let url: URL; let bytes: Int; let sha256: String; var record: PinnedRecord }
public enum KokoroInputs {
  static let hfRepo, hfRevision, sdkRevision: String
  static let packages: [String]; static let voices: [String]
  static let all: [PinnedInput]                       // 21 entries
  static let expectedTreeDigests: [String: String]    // package path to tree_sha256
  static var provenance: Provenance
}
public struct Fetcher: Sendable {
  typealias Download = @Sendable (URL) async throws -> URL
  init(inputs: URL, download: @escaping Download = Fetcher.viaURLSession)
  func isPresent(_ input: PinnedInput) throws -> Bool
  func fetch(_ pinned: [PinnedInput], log: @escaping @Sendable (String) -> Void) async throws
}
public enum FetchError: Error, Equatable { case mismatch(String), http(Int, String) }
```

- [ ] **Step 1: Write the pinned inputs**

Create `Tools/KokoroBundle/PinnedInput.swift`:

```swift
import Foundation

/// One file the bundle is built from: where it comes from, where it lands under the
/// inputs folder, and what its bytes must hash to. A download that does not match is
/// thrown away, never used.
public struct PinnedInput: Sendable, Hashable {
    public let path: String
    public let url: URL
    public let bytes: Int
    public let sha256: String
    public init(path: String, url: URL, bytes: Int, sha256: String) {
        self.path = path
        self.url = url
        self.bytes = bytes
        self.sha256 = sha256
    }
    public var record: PinnedRecord {
        PinnedRecord(path: path, url: url.absoluteString, bytes: bytes, sha256: sha256)
    }
}

/// Every input the Aloud bundle is built from, pinned on 2026-09-14. The model and
/// voice files are one Hugging Face revision of the kokoro-coreml repo; the two runtime
/// assets are the SDK fork's own copies at the revision Aloud pins.
public enum KokoroInputs {
    public static let hfRepo = "mattmireles/kokoro-coreml"
    public static let hfRevision = "9b6c8dbcf1209eedb554ca2fe98e947948061638"
    public static let sdkRevision = "2932a26444b8deba2a6be6c0aa45c0424efaefe1"

    static let hfBase = URL(string: "https://huggingface.co/\(hfRepo)/resolve/\(hfRevision)/")!
    static let sdkBase = URL(
        string:
            "https://raw.githubusercontent.com/kevinxu-cmd/kokoro-coreml/\(sdkRevision)/swift-tts/Sources/KokoroTTS/Resources/KokoroRuntime/"
    )!

    /// The SDK's minimum set: the padded 128-token duration model and the three stages
    /// of the one 15-second bucket.
    public static let packages = [
        "kokoro_duration_t128", "kokoro_f0ntrain_t600", "kokoro_decoder_pre_15s", "kokoro_decoder_har_post_15s",
    ]

    /// The seven voices Aloud ships: four American, three British.
    public static let voices = ["af_bella", "af_sarah", "am_michael", "am_fenrir", "bf_emma", "bm_george", "bm_fable"]

    static func hf(_ path: String, _ bytes: Int, _ sha256: String) -> PinnedInput {
        PinnedInput(path: path, url: URL(string: path, relativeTo: hfBase)!.absoluteURL, bytes: bytes, sha256: sha256)
    }

    static func sdk(_ name: String, _ bytes: Int, _ sha256: String) -> PinnedInput {
        PinnedInput(
            path: "runtime/\(name)", url: URL(string: name, relativeTo: sdkBase)!.absoluteURL, bytes: bytes,
            sha256: sha256)
    }

    public static let all: [PinnedInput] = [
        hf(
            "coreml/kokoro_duration_t128.mlpackage/Manifest.json", 617,
            "51be9ffd007a5c27210ff8e5a6158d44ed66f66ea9647684d9661781f737970f"),
        hf(
            "coreml/kokoro_duration_t128.mlpackage/Data/com.apple.CoreML/model.mlmodel", 5_540_359,
            "ca9a8bca2ba4e3af108351792b9240d590c26b8871afd50578983975885d8c26"),
        hf(
            "coreml/kokoro_duration_t128.mlpackage/Data/com.apple.CoreML/weights/weight.bin", 38_918_912,
            "25db30a2ec864db6b048ce149e980a42dbc9ee2b29fdb8ca956b5a0e8289f1ee"),
        hf(
            "coreml/kokoro_f0ntrain_t600.mlpackage/Manifest.json", 617,
            "a2cdbcc7b3a77e0cf90c3b6c166d654bbb0c6925eef5076bef6b4fe8a12238e3"),
        hf(
            "coreml/kokoro_f0ntrain_t600.mlpackage/Data/com.apple.CoreML/model.mlmodel", 84_755,
            "79050ea4aa8de4252e254e1f90db4b53ea3d233cf27058309dfe0bf4a7b05ff5"),
        hf(
            "coreml/kokoro_f0ntrain_t600.mlpackage/Data/com.apple.CoreML/weights/weight.bin", 20_497_408,
            "5dd6617aba20d23aff99e40667ab008389668defe3813496b8bf45b434bf512f"),
        hf(
            "coreml/kokoro_decoder_pre_15s.mlpackage/Manifest.json", 617,
            "9c6a88ad42d0d3a4743a38e4896acd1707d32555e731a850ab1ba5cd4e5d5095"),
        hf(
            "coreml/kokoro_decoder_pre_15s.mlpackage/Data/com.apple.CoreML/model.mlmodel", 74_522,
            "7fd7fd79ddba7b371cc012c0fe99511a67938d4dbf9364b32b021613ca5e873b"),
        hf(
            "coreml/kokoro_decoder_pre_15s.mlpackage/Data/com.apple.CoreML/weights/weight.bin", 67_190_976,
            "9932a592f367dc61f3912430dbb79a7149c88c09b46e1ee2b57122aac1e05271"),
        hf(
            "coreml/kokoro_decoder_har_post_15s.mlpackage/Manifest.json", 617,
            "2357ffbaed935725d7defa5a689906d559f6b5cf05c124116a5e79df246df1dd"),
        hf(
            "coreml/kokoro_decoder_har_post_15s.mlpackage/Data/com.apple.CoreML/model.mlmodel", 343_289,
            "47a73915a21b2275eb5bc144a6a63c1524d333bbccbaf2bd8b5d45ed747dfcc3"),
        hf(
            "coreml/kokoro_decoder_har_post_15s.mlpackage/Data/com.apple.CoreML/weights/weight.bin", 39_353_848,
            "e4ada8b28c56a4acda6a88e7c6d076aa65a39051841597bc0c4c07a60afe5ac2"),
        hf("kokoro.js/voices/af_bella.bin", 522_240, "f69d836209b78eb8c66e75e3cda491e26ea838a3674257e9d4e5703cbaf55c8b"),
        hf("kokoro.js/voices/af_sarah.bin", 522_240, "4409fbc125afabacc615d94db5398d847006a737b0247d6892b7a9a0007a2f0a"),
        hf("kokoro.js/voices/am_michael.bin", 522_240, "1d1f21dd8da39c30705cd4c75d039d265e9bc4a2a93ed09bc9e1b1225eb95ba1"),
        hf("kokoro.js/voices/am_fenrir.bin", 522_240, "c27989f741f7ee34d273a39d8a595cc0837d35f5ced9a29b7cc162614616df43"),
        hf("kokoro.js/voices/bf_emma.bin", 522_240, "669fe0647f9dd04fcab92f1439a40eeb4c8b4ab1f82e4996fe3d918ce4a63b73"),
        hf("kokoro.js/voices/bm_george.bin", 522_240, "c4b235a4c1f2cd3b939fed08b899ce9385638b763f7b73a59616c4fc9bd6c9bc"),
        hf("kokoro.js/voices/bm_fable.bin", 522_240, "f889083196807b4adb15e9204252165f503b8d33d3982e681c52443c49d798f1"),
        sdk("kokoro-vocab.json", 1159, "353ca94410fde4575cb091a0ba32b8e99077fde4f38fded506f4f041d22571a3"),
        sdk("hnsf_weights.json", 336, "de73b717732da77b31736f67a108d35c478ab116b0a188e9787019b0408c0226"),
    ]

    /// The tree digests upstream's own builder recorded for these four packages at this
    /// revision, from the hosted `KokoroRuntimeManifest.json`. A bundle built here must
    /// reproduce them, which proves the digest code matches upstream's byte for byte.
    public static let expectedTreeDigests: [String: String] = [
        "coreml/kokoro_duration_t128.mlpackage": "9b53f5b289ff633567f70270c57ed68cbd63fc3b320f32caf7b60e4edc2d91e9",
        "coreml/kokoro_f0ntrain_t600.mlpackage": "c01fc9efa172c6360e7eb791677da37528a28425862ea6728123a65f7df8b38b",
        "coreml/kokoro_decoder_pre_15s.mlpackage": "0c2a481aad2af83a9396cb49ca0b2446d073e650f6b37856ba553a64b87ece32",
        "coreml/kokoro_decoder_har_post_15s.mlpackage": "156fbd526c9eac2fc86c46a2fda4485087afaa925548268b560988d71239bae1",
    ]

    public static var provenance: Provenance {
        Provenance(sdkCommit: sdkRevision, hfRepo: hfRepo, hfRevision: hfRevision, inputs: all.map(\.record))
    }
}
```

- [ ] **Step 2: Write the failing fetcher tests**

Create `Tests/KokoroBundleTests/FetcherTests.swift`:

```swift
import Foundation
import Testing

@testable import KokoroBundle

@Suite struct FetcherTests {
    func scratch() throws -> URL {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        return url
    }

    /// A pinned input whose "download" is a local file, so the fetcher can be driven
    /// without a network.
    func pinned(_ data: Data, path: String = "kokoro.js/voices/af_bella.bin", sha256: String? = nil) throws -> (
        PinnedInput, URL
    ) {
        let served = try scratch().appendingPathComponent("served.bin")
        try data.write(to: served)
        let input = PinnedInput(path: path, url: served, bytes: data.count, sha256: sha256 ?? Digest.sha256(of: data))
        return (input, served)
    }

    /// Serves by copying, so a moved temp file never eats the source, and counts calls.
    final class Server: @unchecked Sendable {
        let lock = NSLock()
        var calls = 0
        func download(_ url: URL) throws -> URL {
            lock.withLock { calls += 1 }
            let tmp = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
            try FileManager.default.copyItem(at: url, to: tmp)
            return tmp
        }
    }

    @Test func aMissingInputIsFetchedAndVerified() async throws {
        let inputs = try scratch()
        let (input, _) = try pinned(Data(count: 1024))
        let server = Server()
        let fetcher = Fetcher(inputs: inputs) { try server.download($0) }

        try await fetcher.fetch([input]) { _ in }

        #expect(try fetcher.isPresent(input))
        #expect(try Data(contentsOf: inputs.appendingPathComponent(input.path)) == Data(count: 1024))
        #expect(server.calls == 1)
    }

    @Test func aPresentAndMatchingInputIsNotFetchedAgain() async throws {
        let inputs = try scratch()
        let (input, _) = try pinned(Data(count: 1024))
        let server = Server()
        let fetcher = Fetcher(inputs: inputs) { try server.download($0) }

        try await fetcher.fetch([input]) { _ in }
        try await fetcher.fetch([input]) { _ in }

        #expect(server.calls == 1)
    }

    /// A file on disk with the right size and the wrong bytes is fetched again, and one
    /// whose download does not match is thrown away and the run fails.
    @Test func aMismatchIsDiscarded() async throws {
        let inputs = try scratch()
        let (input, _) = try pinned(Data(count: 1024), sha256: String(repeating: "0", count: 64))
        let server = Server()
        let fetcher = Fetcher(inputs: inputs) { try server.download($0) }

        await #expect(throws: FetchError.mismatch("kokoro.js/voices/af_bella.bin")) {
            try await fetcher.fetch([input]) { _ in }
        }
        #expect(!FileManager.default.fileExists(atPath: inputs.appendingPathComponent(input.path).path))
    }

    @Test func aStaleFileWithTheRightSizeIsReplaced() async throws {
        let inputs = try scratch()
        var good = Data(count: 1024)
        good[0] = 1
        let (input, _) = try pinned(good)
        let stale = inputs.appendingPathComponent(input.path)
        try FileManager.default.createDirectory(at: stale.deletingLastPathComponent(), withIntermediateDirectories: true)
        try Data(count: 1024).write(to: stale)
        let server = Server()
        let fetcher = Fetcher(inputs: inputs) { try server.download($0) }

        #expect(try !fetcher.isPresent(input))
        try await fetcher.fetch([input]) { _ in }

        #expect(server.calls == 1)
        #expect(try Data(contentsOf: stale) == good)
    }

    /// The pinned list is what the bundle is: four packages of three files, seven
    /// voices, two assets, every path inside the inputs folder.
    @Test func thePinnedListIsComplete() {
        let paths = KokoroInputs.all.map(\.path)
        #expect(paths.count == 21)
        #expect(Set(paths).count == 21)
        for name in KokoroInputs.packages {
            for file in ["Manifest.json", "Data/com.apple.CoreML/model.mlmodel", "Data/com.apple.CoreML/weights/weight.bin"] {
                #expect(paths.contains("coreml/\(name).mlpackage/\(file)"), "\(name)/\(file)")
            }
        }
        for voice in KokoroInputs.voices {
            #expect(paths.contains("kokoro.js/voices/\(voice).bin"), voice)
        }
        #expect(paths.contains("runtime/kokoro-vocab.json"))
        #expect(paths.contains("runtime/hnsf_weights.json"))
        #expect(KokoroInputs.all.allSatisfy { $0.sha256.count == 64 && !$0.path.hasPrefix("/") && !$0.path.contains("..") })
        #expect(KokoroInputs.all.filter { $0.path.hasPrefix("kokoro.js/") }.allSatisfy { $0.bytes == 522_240 })
        #expect(Set(KokoroInputs.expectedTreeDigests.keys) == Set(KokoroInputs.packages.map { "coreml/\($0).mlpackage" }))
    }
}
```

- [ ] **Step 3: Run to see them fail**

```bash
swift test --filter FetcherTests 2>&1 | grep -E "error:" | head -3
```

Expected: `cannot find 'Fetcher' in scope`.

- [ ] **Step 4: Implement the fetcher**

Create `Tools/KokoroBundle/Fetcher.swift`:

```swift
import Foundation

public enum FetchError: Error, Equatable {
    case mismatch(String)
    case http(Int, String)
}

/// Fills the inputs folder against the pinned list. A file already there with the right
/// size and hash is left alone; anything else is downloaded to a temporary file, moved
/// into place, and checked again before it counts.
public struct Fetcher: Sendable {
    public typealias Download = @Sendable (URL) async throws -> URL

    public let inputs: URL
    let download: Download

    public init(inputs: URL, download: @escaping Download = Fetcher.viaURLSession) {
        self.inputs = inputs
        self.download = download
    }

    /// The default download: the shared session, to a temporary file, refusing anything
    /// but a 200.
    public static let viaURLSession: Download = { url in
        let (file, response) = try await URLSession.shared.download(from: url)
        if let http = response as? HTTPURLResponse, http.statusCode != 200 {
            try? FileManager.default.removeItem(at: file)
            throw FetchError.http(http.statusCode, url.absoluteString)
        }
        return file
    }

    public func isPresent(_ input: PinnedInput) throws -> Bool {
        let url = inputs.appendingPathComponent(input.path)
        guard FileManager.default.fileExists(atPath: url.path) else { return false }
        guard try url.resourceValues(forKeys: [.fileSizeKey]).fileSize == input.bytes else { return false }
        return try Digest.sha256(ofFileAt: url) == input.sha256
    }

    public func fetch(_ pinned: [PinnedInput], log: @escaping @Sendable (String) -> Void) async throws {
        for input in pinned {
            if try isPresent(input) { continue }
            log("fetching \(input.path)")
            let temporary = try await download(input.url)
            let destination = inputs.appendingPathComponent(input.path)
            try FileManager.default.createDirectory(
                at: destination.deletingLastPathComponent(), withIntermediateDirectories: true)
            try? FileManager.default.removeItem(at: destination)
            try FileManager.default.moveItem(at: temporary, to: destination)
            guard try isPresent(input) else {
                try? FileManager.default.removeItem(at: destination)
                throw FetchError.mismatch(input.path)
            }
        }
    }
}
```

- [ ] **Step 5: Run the fetcher tests**

```bash
swift test --filter FetcherTests 2>&1 | grep -E "Test .* (passed|failed)|error:" | tail -7
```

Expected: five passes.

- [ ] **Step 6: Check and commit**

```bash
make check 2>&1 | tail -3
git add Tools/KokoroBundle/PinnedInput.swift Tools/KokoroBundle/Fetcher.swift Tests/KokoroBundleTests/FetcherTests.swift
git commit -m "The bundle's inputs are pinned by checksum, and the fetcher fills them in"
```

---

### Task 5: The command, the Makefile target, the first real build, and the parity proof

**Files:**
- Create: `Tools/kokoro-bundle/main.swift`
- Modify: `Makefile`
- Test: `Tests/KokoroBundleTests/ParityTests.swift`

**Interfaces:**
- Consumes: everything above.
- Produces: `.build/kokoro-bundle/kokoro-1.aar` and `.build/kokoro-bundle/kokoro-1.aar.sha256`, and the numbers plan 3 pins: the archive's SHA-256 and byte count.

- [ ] **Step 1: Write the gated parity test**

Create `Tests/KokoroBundleTests/ParityTests.swift`:

```swift
import Foundation
import Testing

@testable import KokoroBundle

/// Runs only once `make kokoro-bundle` has filled `.build/kokoro-inputs` on this machine.
/// It builds the real bundle into a temporary folder and checks the four package tree
/// digests against the ones upstream's own builder recorded for the same files, which
/// is the proof that the Swift digest code and upstream's JavaScript agree byte for byte.
@Suite struct ParityTests {
    static let packageRoot = URL(fileURLWithPath: #filePath)
        .deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
    static let inputs = packageRoot.appendingPathComponent(".build/kokoro-inputs")

    @Test(.enabled(if: ParityTests.allInputsPresent()))
    func theTreeDigestsMatchUpstreams() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        let manifest = try BundleBuilder(
            inputs: Self.inputs, packages: KokoroInputs.packages, voices: KokoroInputs.voices
        ).build(into: root, provenance: KokoroInputs.provenance)
        for package in manifest.modelPackages {
            #expect(package.treeSHA256 == KokoroInputs.expectedTreeDigests[package.path], package.path)
            #expect(package.fileCount == 3, package.path)
        }
        #expect(manifest.modelPackages.map(\.bytes) == [44_459_888, 20_582_780, 67_266_115, 39_697_754])
        try? FileManager.default.removeItem(at: root)
    }

    static func allInputsPresent() -> Bool {
        let fetcher = Fetcher(inputs: inputs)
        return KokoroInputs.all.allSatisfy { (try? fetcher.isPresent($0)) == true }
    }
}
```

- [ ] **Step 2: Write the command**

Create `Tools/kokoro-bundle/main.swift`:

```swift
import Foundation
import KokoroBundle

// Builds the Kokoro model bundle Aloud downloads on first use.
//
//     swift run -c release kokoro-bundle [--version 1] [--inputs .build/kokoro-inputs] [--out .build/kokoro-bundle]
//
// The inputs are fetched against pinned checksums the first time and reused after. The
// output is `kokoro-<version>.aar` and a sidecar with its SHA-256, both under `--out`.

let arguments = CommandLine.arguments

func option(_ name: String, default fallback: String) -> String {
    guard let index = arguments.firstIndex(of: name), index + 1 < arguments.count else { return fallback }
    return arguments[index + 1]
}

let version = option("--version", default: "1")
let inputs = URL(fileURLWithPath: option("--inputs", default: ".build/kokoro-inputs"))
let out = URL(fileURLWithPath: option("--out", default: ".build/kokoro-bundle"))
let name = "kokoro-\(version)"

let fetcher = Fetcher(inputs: inputs)
try await fetcher.fetch(KokoroInputs.all) { print($0) }
print("inputs complete: \(KokoroInputs.all.count) files under \(inputs.path)")

let root = out.appendingPathComponent(name)
let manifest = try BundleBuilder(inputs: inputs, packages: KokoroInputs.packages, voices: KokoroInputs.voices)
    .build(into: root, provenance: KokoroInputs.provenance)
for package in manifest.modelPackages {
    let mark = package.treeSHA256 == KokoroInputs.expectedTreeDigests[package.path] ? "matches upstream" : "DIFFERS"
    print("\(package.path): \(package.treeSHA256) \(mark)")
}
guard manifest.modelPackages.allSatisfy({ $0.treeSHA256 == KokoroInputs.expectedTreeDigests[$0.path] }) else {
    print("a package digest differs from the one upstream recorded; not archiving")
    exit(1)
}

let archive = out.appendingPathComponent("\(name).aar")
try AppleArchiveFile.compress(directory: root, to: archive)
let sha256 = try Digest.sha256(ofFileAt: archive)
let bytes = try archive.resourceValues(forKeys: [.fileSizeKey]).fileSize ?? 0
try "\(sha256)  \(name).aar\n".write(to: out.appendingPathComponent("\(name).aar.sha256"), atomically: true, encoding: .utf8)
print("\(archive.path)")
print("bytes: \(bytes)")
print("sha256: \(sha256)")
```

- [ ] **Step 3: Add the Makefile targets**

Add `kokoro-bundle kokoro-release` to the `.PHONY` line, and add after the `icon` target:

```makefile
# The Kokoro model bundle the app downloads on first use: pinned inputs in, one Apple
# Archive and its checksum out, under .build/kokoro-bundle. The first run downloads
# about 180 MB; later runs reuse the verified inputs.
KOKORO_VERSION := 1
KOKORO_OUT := .build/kokoro-bundle

kokoro-bundle:
	swift run -c release kokoro-bundle --version $(KOKORO_VERSION) --out $(KOKORO_OUT)

# Attaches the archive to the kokoro-models release on the Aloud repo, creating the
# release the first time. The release is its own tag so the model does not churn with
# app releases. Needs `gh` logged in with push rights.
kokoro-release: kokoro-bundle
	gh release view kokoro-models >/dev/null 2>&1 || gh release create kokoro-models \
		--title "Kokoro models" \
		--notes "The Kokoro voice models Aloud downloads on first use. Built by make kokoro-bundle from pinned Hugging Face inputs; the .sha256 sidecar is what the app checks."
	gh release upload kokoro-models $(KOKORO_OUT)/kokoro-$(KOKORO_VERSION).aar $(KOKORO_OUT)/kokoro-$(KOKORO_VERSION).aar.sha256 --clobber
```

- [ ] **Step 4: Run the first real build**

```bash
cd /Users/kevindazoo/aloud
time make kokoro-bundle 2>&1 | tail -12
```

Expected: 21 `fetching` lines the first time (about 180 MB from Hugging Face and GitHub; allow ten minutes on a slow connection), then four `matches upstream` lines, the archive path, `bytes:` and `sha256:`.
The archive should be roughly 165 to 180 MB: the weights are half-precision and compress little.
Write the printed `bytes` and `sha256` down; plan 3 pins them.

If any `DIFFERS` line appears, do not proceed: compare that package's `files` list against the pinned inputs (all three files must be present with the pinned sizes), and check `Digest.package` orders by relative path.

- [ ] **Step 5: Run the parity test and the whole suite**

```bash
swift test --filter ParityTests 2>&1 | grep -E "Test .* (passed|failed|skipped)|error:" | tail -3
make test 2>&1 | grep -E "Test run|passed|failed" | tail -3
```

Expected: `theTreeDigestsMatchUpstreams` passes now that the inputs are present, and the whole suite passes.

- [ ] **Step 6: Confirm the archive is reproducible and loads through the SDK**

```bash
cp .build/kokoro-bundle/kokoro-1.aar /tmp/kokoro-1-first.aar
make kokoro-bundle >/dev/null 2>&1
cmp /tmp/kokoro-1-first.aar .build/kokoro-bundle/kokoro-1.aar && echo "byte-identical rebuild"
ls -la .build/kokoro-bundle/kokoro-1/
```

Expected: `byte-identical rebuild`, and the listing shows `KokoroRuntimeManifest.json`, `AloudDownloadManifest.json`, `coreml`, `voices`, `runtime`.

Then the real load, through the gated integration test plan 3 adds, or directly now with the consumer trick from plan 1: a throwaway package that depends on the SDK and runs:

```swift
import KokoroTTS
let root = URL(fileURLWithPath: CommandLine.arguments[1])
let cache = FileManager.default.temporaryDirectory.appendingPathComponent("kokoro-cache")
let tts = try await KokoroTTS.load(resources: .directory(root, compiledModelsDirectory: cache))
try await tts.prewarm(text: "Nobody really teaches you research.", voice: KokoroVoiceID("af_bella"))
let audio = try await tts.synthesize("Nobody really teaches you research.", voice: KokoroVoiceID("bm_fable"))
print("seconds:", audio.durationSeconds, "finite:", audio.samples.allSatisfy(\.isFinite))
```

run against `.build/kokoro-bundle/kokoro-1`.
Expected: a duration between one and four seconds and `finite: true`.
The first prewarm compiles the four models and takes tens of seconds; that is the once-per-install cost the spec describes.
Remove the throwaway package afterwards.

- [ ] **Step 7: Check and commit**

```bash
make check 2>&1 | tail -3
git status --short
git add Tools/kokoro-bundle/main.swift Makefile Tests/KokoroBundleTests/ParityTests.swift
git commit -m "make kokoro-bundle builds the model archive from pinned inputs and proves its digests"
```

`git status` must show nothing under `.build/`; it is ignored.

---

### Task 6: Publish the archive

**Files:**
- None new.

**Interfaces:**
- Produces: the release `kokoro-models` on `kevxuUmich/Aloud` with `kokoro-1.aar` and `kokoro-1.aar.sha256` attached, and the three values plan 3 pins in `KokoroRelease`: the asset URL `https://github.com/kevxuUmich/Aloud/releases/download/kokoro-models/kokoro-1.aar`, the archive's SHA-256, and its byte count.
  Since this plan ran, the final fix wave built the four-bucket bundle and published `kokoro-2.aar` beside these two under the same tag, and `KOKORO_VERSION` in the Makefile is 2.
  `kokoro-1.aar` is untouched.

This creates a public release on the Aloud repository.
It is outward-facing: confirm the go-ahead before running it if it was not given with the plan.

- [ ] **Step 1: Create the release and upload**

```bash
cd /Users/kevindazoo/aloud
make kokoro-release 2>&1 | tail -5
gh release view kokoro-models --json assets -q '.assets[] | "\(.name) \(.size)"'
```

Expected: two assets, `kokoro-1.aar` with the byte count from Task 5 and `kokoro-1.aar.sha256`.

- [ ] **Step 2: Verify the download the way the app will**

```bash
cd /tmp && rm -f kokoro-1.aar
curl -sL -o kokoro-1.aar https://github.com/kevxuUmich/Aloud/releases/download/kokoro-models/kokoro-1.aar
shasum -a 256 kokoro-1.aar
curl -sL https://github.com/kevxuUmich/Aloud/releases/download/kokoro-models/kokoro-1.aar.sha256
```

Expected: the two printed hashes match each other and the `sha256:` line from Task 5.

- [ ] **Step 3: Record what plan 3 needs**

Write the three values into the ledger or the handoff note:

```text
KokoroRelease.url     = https://github.com/kevxuUmich/Aloud/releases/download/kokoro-models/kokoro-1.aar
KokoroRelease.version = "1"
KokoroRelease.sha256  = <64 hex from Task 5>
KokoroRelease.bytes   = <byte count from Task 5>
```

Nothing is committed in this task; the release is the artefact.

---

## Self-review against the spec

- "A Swift script in `Tools/`, run as `make kokoro-bundle`": the tool lives under `Tools/` as a SwiftPM executable and library rather than a single script file, because the spec's own testing section asks for a test that builds a bundle and loads it through the SDK, and a script cannot be linked against the SDK in a test. `make kokoro-bundle` is the entry point either way.
- "Downloads them into `.build` against pinned checksums, so a rebuild on another machine produces a byte-identical bundle": Task 4 pins 21 files by URL, size and SHA-256; Task 3 fixes the archive's field set so times and owners do not enter it; Task 2 normalises permissions and encodes the manifest with sorted keys and no timestamp; Task 5 step 6 checks the rebuild is byte-identical.
- "Computes every per-file digest and per-package tree digest with the SDK's own rules": Task 1, with Task 5's gated test reproducing upstream's recorded tree digests.
- "Sets the provenance flag. The bundle profile is named `aloud`": Task 2.
- "One Apple Archive, `kokoro-<version>.aar`, compressed, about 165 MB, and a sidecar text file with its SHA-256": Task 5. The exact size is measured there.
- "Attached to a release tagged `kokoro-models` on the Aloud repo": Task 6.
- "The four models are the SDK's minimum set": the pinned packages are the padded 128-token duration model and the three 15-second bucket stages.
- "A test that builds a bundle from local fixture files and loads it through the SDK": Task 2's `theSDKLoadsWhatTheBuilderWrites` and `aTamperedVoiceIsRefusedBySDK`.
- Placeholder scan: the only values not written in this plan are the archive's SHA-256 and byte count, which exist only once Task 5 has run; the plan says where they are printed and where plan 3 pins them.
- Type consistency: `Digest.package(at:path:)` returns `PackageDigest` with `treeSHA256`, used by `BundleBuilder`, `ParityTests` and `main.swift` under that name; `Provenance` and `PinnedRecord` are declared in `BundleBuilder.swift` and used by `PinnedInput.swift` and the tests with the same labels; `Fetcher.isPresent(_:)` is used by `ParityTests` and `main.swift`.
