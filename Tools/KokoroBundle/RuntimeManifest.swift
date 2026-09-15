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
