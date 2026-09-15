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
            let destination = try copy(
                "kokoro.js/voices/\(id).bin", to: root.appendingPathComponent("voices/\(id).bin"))
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
            runtimeAssets: .init(
                vocab: assets["kokoro-vocab.json"]!, hnsfWeights: assets["hnsf_weights.json"]!))
        try manifest.encoded().write(to: root.appendingPathComponent(RuntimeManifest.fileName))
        try Self.normalisePermissions(under: root)
        return manifest
    }

    private func copy(_ relative: String, to destination: URL) throws -> URL {
        let source = inputs.appendingPathComponent(relative)
        guard FileManager.default.fileExists(atPath: source.path) else {
            throw BuildError.missingInput(relative)
        }
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
