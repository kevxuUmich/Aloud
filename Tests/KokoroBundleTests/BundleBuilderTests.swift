import Foundation
import KokoroTTS
import Testing

@testable import KokoroBundle

@Suite struct BundleBuilderTests {
    static let voices = [
        "af_bella", "af_sarah", "am_michael", "am_fenrir", "bf_emma", "bm_george", "bm_fable",
    ]
    static let packages = [
        "kokoro_duration_t128", "kokoro_f0ntrain_t600", "kokoro_decoder_pre_15s",
        "kokoro_decoder_har_post_15s",
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
        try fm.createDirectory(
            at: inputs.appendingPathComponent("kokoro.js/voices"), withIntermediateDirectories: true)
        for (i, id) in Self.voices.enumerated() {
            var row = Data(count: 256 * 4)
            row[0] = UInt8(i + 1)
            try row.write(to: inputs.appendingPathComponent("kokoro.js/voices/\(id).bin"))
        }
        try fm.createDirectory(
            at: inputs.appendingPathComponent("runtime"), withIntermediateDirectories: true)
        for name in ["kokoro-vocab.json", "hnsf_weights.json"] {
            let src = try #require(
                Bundle.module.url(forResource: name, withExtension: nil, subdirectory: "Fixtures"))
            try fm.copyItem(at: src, to: inputs.appendingPathComponent("runtime/\(name)"))
        }
        return inputs
    }

    var provenance: Provenance {
        Provenance(
            sdkCommit: "2932a26444b8deba2a6be6c0aa45c0424efaefe1", hfRepo: "mattmireles/kokoro-coreml",
            hfRevision: "9b6c8dbcf1209eedb554ca2fe98e947948061638",
            inputs: [
                PinnedRecord(
                    path: "coreml/x", url: "https://example.invalid/x", bytes: 1,
                    sha256: String(repeating: "a", count: 64))
            ])
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
        #expect(
            m.runtimeAssets.vocab.sha256 == "353ca94410fde4575cb091a0ba32b8e99077fde4f38fded506f4f041d22571a3"
        )
        #expect(
            m.runtimeAssets.hnsfWeights.sha256
                == "de73b717732da77b31736f67a108d35c478ab116b0a188e9787019b0408c0226")
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
        #expect(
            try FileManager.default.attributesOfItem(atPath: file.path)[.posixPermissions] as? Int == 0o644)
        #expect(
            try FileManager.default.attributesOfItem(atPath: dir.path)[.posixPermissions] as? Int == 0o755)
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
