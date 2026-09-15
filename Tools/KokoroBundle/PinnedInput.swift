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

    /// The padded 128-token duration model and the three stages of each of the four
    /// acoustic buckets. The SDK renders a sentence over the whole of the bucket it
    /// picks, so a bundle with only the 15-second bucket makes a three-second sentence
    /// cost what a fifteen-second one does; the short buckets are where the wall clock
    /// goes. Each bucket needs its `kokoro_f0ntrain_t<tFrames>`, `kokoro_decoder_pre_<n>s`
    /// and `kokoro_decoder_har_post_<n>s`, with tFrames 120, 280, 400 and 600 for 3, 7,
    /// 10 and 15 seconds.
    public static let packages = [
        "kokoro_duration_t128",
        "kokoro_f0ntrain_t120", "kokoro_f0ntrain_t280", "kokoro_f0ntrain_t400", "kokoro_f0ntrain_t600",
        "kokoro_decoder_pre_3s", "kokoro_decoder_pre_7s", "kokoro_decoder_pre_10s", "kokoro_decoder_pre_15s",
        "kokoro_decoder_har_post_3s", "kokoro_decoder_har_post_7s", "kokoro_decoder_har_post_10s",
        "kokoro_decoder_har_post_15s",
    ]

    /// The bucket seconds the manifest declares, one per acoustic triple above.
    public static let buckets = [3, 7, 10, 15]

    /// The seven voices Aloud ships: four American, three British.
    public static let voices = [
        "af_bella", "af_sarah", "am_michael", "am_fenrir", "bf_emma", "bm_george", "bm_fable",
    ]

    static func hf(_ path: String, _ bytes: Int, _ sha256: String) -> PinnedInput {
        PinnedInput(
            path: path, url: URL(string: path, relativeTo: hfBase)!.absoluteURL, bytes: bytes, sha256: sha256)
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
            "coreml/kokoro_f0ntrain_t120.mlpackage/Manifest.json", 617,
            "c81c0442ab6bf894f8490728ca6aec885e7e297421fb792cf166ca5409e11f33"),
        hf(
            "coreml/kokoro_f0ntrain_t120.mlpackage/Data/com.apple.CoreML/model.mlmodel", 84_673,
            "67291d43eabecc46cc5ad9fe9a52288d4f31dd2c2b936244949f96e03cb5f9ad"),
        hf(
            "coreml/kokoro_f0ntrain_t120.mlpackage/Data/com.apple.CoreML/weights/weight.bin", 20_497_408,
            "5dd6617aba20d23aff99e40667ab008389668defe3813496b8bf45b434bf512f"),
        hf(
            "coreml/kokoro_f0ntrain_t280.mlpackage/Manifest.json", 617,
            "06ec0b3545675e8de0fba2f45303a6034a5e731dcba87edb3f2b8e3fef794fef"),
        hf(
            "coreml/kokoro_f0ntrain_t280.mlpackage/Data/com.apple.CoreML/model.mlmodel", 84_755,
            "378ed8776331a2a3a2e9fd6d76ff23156da0e2e06e3ec0e3e63bd6a0eed3b6d4"),
        hf(
            "coreml/kokoro_f0ntrain_t280.mlpackage/Data/com.apple.CoreML/weights/weight.bin", 20_497_408,
            "5dd6617aba20d23aff99e40667ab008389668defe3813496b8bf45b434bf512f"),
        hf(
            "coreml/kokoro_f0ntrain_t400.mlpackage/Manifest.json", 617,
            "b056e74fafac571a3d1c021a18df25364affd21f98534d9392e4c0abc9eb5fbb"),
        hf(
            "coreml/kokoro_f0ntrain_t400.mlpackage/Data/com.apple.CoreML/model.mlmodel", 84_755,
            "48ca73b747c7775dca90f71ae47d32830d4041695bb893dcf55c0aa2c0de1d5a"),
        hf(
            "coreml/kokoro_f0ntrain_t400.mlpackage/Data/com.apple.CoreML/weights/weight.bin", 20_497_408,
            "5dd6617aba20d23aff99e40667ab008389668defe3813496b8bf45b434bf512f"),
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
            "coreml/kokoro_decoder_pre_3s.mlpackage/Manifest.json", 617,
            "5e61e5597104580caaa190c21a0afc1d783ad326fcb0d240e577805bc97d4f1d"),
        hf(
            "coreml/kokoro_decoder_pre_3s.mlpackage/Data/com.apple.CoreML/model.mlmodel", 74_390,
            "5ed79fec1d9810b3ac781998e1e70f7e9d43567342316187414323988e5784af"),
        hf(
            "coreml/kokoro_decoder_pre_3s.mlpackage/Data/com.apple.CoreML/weights/weight.bin", 67_190_976,
            "9932a592f367dc61f3912430dbb79a7149c88c09b46e1ee2b57122aac1e05271"),
        hf(
            "coreml/kokoro_decoder_pre_7s.mlpackage/Manifest.json", 617,
            "181d66a4e4b7b63ca3ec33a5c44ee41a56f8726a2aa93532ec2a516e3a8ce57a"),
        hf(
            "coreml/kokoro_decoder_pre_7s.mlpackage/Data/com.apple.CoreML/model.mlmodel", 74_522,
            "f0238e53ab2c6196e2f4899def1b1f475bbe64e4901c67dd2b83a0396da224c5"),
        hf(
            "coreml/kokoro_decoder_pre_7s.mlpackage/Data/com.apple.CoreML/weights/weight.bin", 67_190_976,
            "9932a592f367dc61f3912430dbb79a7149c88c09b46e1ee2b57122aac1e05271"),
        hf(
            "coreml/kokoro_decoder_pre_10s.mlpackage/Manifest.json", 617,
            "43ee484278c2fcaf498fe531b4efa69014ff1653e2b5e1f2dfca3854ea3d5f25"),
        hf(
            "coreml/kokoro_decoder_pre_10s.mlpackage/Data/com.apple.CoreML/model.mlmodel", 74_522,
            "38a08acf75e254bb3f2d3a894b4972ef06a5c5cc9e5d39e68c590280d96854c5"),
        hf(
            "coreml/kokoro_decoder_pre_10s.mlpackage/Data/com.apple.CoreML/weights/weight.bin", 67_190_976,
            "9932a592f367dc61f3912430dbb79a7149c88c09b46e1ee2b57122aac1e05271"),
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
            "coreml/kokoro_decoder_har_post_3s.mlpackage/Manifest.json", 617,
            "f1a7d769e41016747fd556e5aea79c11e328c907786d3a2dbf3e5b0e88ea6f64"),
        hf(
            "coreml/kokoro_decoder_har_post_3s.mlpackage/Data/com.apple.CoreML/model.mlmodel", 342_876,
            "6050b421ac1b3785c1b99211d25835fec1f57e3c347c51673bec0ccab1f70113"),
        hf(
            "coreml/kokoro_decoder_har_post_3s.mlpackage/Data/com.apple.CoreML/weights/weight.bin",
            39_353_848,
            "e4ada8b28c56a4acda6a88e7c6d076aa65a39051841597bc0c4c07a60afe5ac2"),
        hf(
            "coreml/kokoro_decoder_har_post_7s.mlpackage/Manifest.json", 617,
            "2209b06682d17218aa75c20a31a82cfa02a8e62646085fc9057a9c5caf80cc62"),
        hf(
            "coreml/kokoro_decoder_har_post_7s.mlpackage/Data/com.apple.CoreML/model.mlmodel", 343_189,
            "76bdb21faa36286934aae9e3ad9ddb1e78f43051cfb9986924f21a95c7cd66be"),
        hf(
            "coreml/kokoro_decoder_har_post_7s.mlpackage/Data/com.apple.CoreML/weights/weight.bin",
            39_353_848,
            "e4ada8b28c56a4acda6a88e7c6d076aa65a39051841597bc0c4c07a60afe5ac2"),
        hf(
            "coreml/kokoro_decoder_har_post_10s.mlpackage/Manifest.json", 617,
            "b87b5ea3aaba0895273b008f8318632ac46d0d2e50a3533b583198eff9ecc449"),
        hf(
            "coreml/kokoro_decoder_har_post_10s.mlpackage/Data/com.apple.CoreML/model.mlmodel", 343_189,
            "ecac9febb39839f624cc8df7f421e16cd1d6c4e6e7e043a643f02f8fea600b99"),
        hf(
            "coreml/kokoro_decoder_har_post_10s.mlpackage/Data/com.apple.CoreML/weights/weight.bin",
            39_353_848,
            "e4ada8b28c56a4acda6a88e7c6d076aa65a39051841597bc0c4c07a60afe5ac2"),
        hf(
            "coreml/kokoro_decoder_har_post_15s.mlpackage/Manifest.json", 617,
            "2357ffbaed935725d7defa5a689906d559f6b5cf05c124116a5e79df246df1dd"),
        hf(
            "coreml/kokoro_decoder_har_post_15s.mlpackage/Data/com.apple.CoreML/model.mlmodel", 343_289,
            "47a73915a21b2275eb5bc144a6a63c1524d333bbccbaf2bd8b5d45ed747dfcc3"),
        hf(
            "coreml/kokoro_decoder_har_post_15s.mlpackage/Data/com.apple.CoreML/weights/weight.bin",
            39_353_848,
            "e4ada8b28c56a4acda6a88e7c6d076aa65a39051841597bc0c4c07a60afe5ac2"),
        hf(
            "kokoro.js/voices/af_bella.bin", 522_240,
            "f69d836209b78eb8c66e75e3cda491e26ea838a3674257e9d4e5703cbaf55c8b"),
        hf(
            "kokoro.js/voices/af_sarah.bin", 522_240,
            "4409fbc125afabacc615d94db5398d847006a737b0247d6892b7a9a0007a2f0a"),
        hf(
            "kokoro.js/voices/am_michael.bin", 522_240,
            "1d1f21dd8da39c30705cd4c75d039d265e9bc4a2a93ed09bc9e1b1225eb95ba1"),
        hf(
            "kokoro.js/voices/am_fenrir.bin", 522_240,
            "c27989f741f7ee34d273a39d8a595cc0837d35f5ced9a29b7cc162614616df43"),
        hf(
            "kokoro.js/voices/bf_emma.bin", 522_240,
            "669fe0647f9dd04fcab92f1439a40eeb4c8b4ab1f82e4996fe3d918ce4a63b73"),
        hf(
            "kokoro.js/voices/bm_george.bin", 522_240,
            "c4b235a4c1f2cd3b939fed08b899ce9385638b763f7b73a59616c4fc9bd6c9bc"),
        hf(
            "kokoro.js/voices/bm_fable.bin", 522_240,
            "f889083196807b4adb15e9204252165f503b8d33d3982e681c52443c49d798f1"),
        sdk("kokoro-vocab.json", 1159, "353ca94410fde4575cb091a0ba32b8e99077fde4f38fded506f4f041d22571a3"),
        sdk("hnsf_weights.json", 336, "de73b717732da77b31736f67a108d35c478ab116b0a188e9787019b0408c0226"),
    ]

    /// The tree digests upstream's own builder recorded for these four packages at this
    /// revision, from the hosted `KokoroRuntimeManifest.json`. A bundle built here must
    /// reproduce them, which proves the digest code matches upstream's byte for byte.
    public static let expectedTreeDigests: [String: String] = [
        "coreml/kokoro_duration_t128.mlpackage":
            "9b53f5b289ff633567f70270c57ed68cbd63fc3b320f32caf7b60e4edc2d91e9",
        "coreml/kokoro_f0ntrain_t600.mlpackage":
            "c01fc9efa172c6360e7eb791677da37528a28425862ea6728123a65f7df8b38b",
        "coreml/kokoro_decoder_pre_15s.mlpackage":
            "0c2a481aad2af83a9396cb49ca0b2446d073e650f6b37856ba553a64b87ece32",
        "coreml/kokoro_decoder_har_post_15s.mlpackage":
            "156fbd526c9eac2fc86c46a2fda4485087afaa925548268b560988d71239bae1",
    ]

    /// Not upstream's. Upstream's hosted manifest at this revision declares only the
    /// 15-second bucket, so for the nine packages the short buckets added there is
    /// nothing of upstream's to compare against. These are the digests this repository's
    /// own first build computed from the pinned files, recorded so that a later build
    /// that comes out different is refused rather than quietly shipped. They prove
    /// nothing about agreement with upstream's builder; `expectedTreeDigests` above is
    /// what proves that, and it is the same digest code over both sets.
    public static let recordedTreeDigests: [String: String] = [
        "coreml/kokoro_f0ntrain_t120.mlpackage":
            "8480e5bd851985aa1c508f9d977add23db8d8cae369ee28de278d031d3d0b1f8",
        "coreml/kokoro_f0ntrain_t280.mlpackage":
            "3e212c0e71c7919052b233a629e98d09ffdde2b377dd601ebfa4e74e05aa6a33",
        "coreml/kokoro_f0ntrain_t400.mlpackage":
            "2607fe1b266fabc67d711f20b1b235698513599ac4d3b9a026cad1dc1fece652",
        "coreml/kokoro_decoder_pre_3s.mlpackage":
            "5f1d39c04dd0c18aa01cb5657846bbc16237a9a7d7cf1573108ef653bf134f17",
        "coreml/kokoro_decoder_pre_7s.mlpackage":
            "f607e8137dd5937b35aec4b3ed013a2377c492d895ebccec490347b94b7ff080",
        "coreml/kokoro_decoder_pre_10s.mlpackage":
            "fec63fb9d986525803e41f46263210095e37851d02c4f12ec46a129f2fd83341",
        "coreml/kokoro_decoder_har_post_3s.mlpackage":
            "83c92b4854929713545999b77aac1c0525b1634925e985c82482a57669809704",
        "coreml/kokoro_decoder_har_post_7s.mlpackage":
            "00f944548c54b3e3649b1ace800c96ebf784f980b8f85eaee7f43a54f9bda5dd",
        "coreml/kokoro_decoder_har_post_10s.mlpackage":
            "4245c65012624d9395d5aacd704dcaf7b3c911025bd4bdc6882dd2a85ce8cc5c",
    ]

    /// Every package's pinned tree digest, upstream's where upstream has one and this
    /// repository's own record where it does not.
    public static var treeDigests: [String: String] {
        expectedTreeDigests.merging(recordedTreeDigests) { upstream, _ in upstream }
    }

    public static var provenance: Provenance {
        Provenance(sdkCommit: sdkRevision, hfRepo: hfRepo, hfRevision: hfRevision, inputs: all.map(\.record))
    }
}
