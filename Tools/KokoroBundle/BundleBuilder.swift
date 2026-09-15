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
    /// Every file the bundle may contain, by its path under the inputs folder; build()
    /// refuses a file with no record or a record that does not match.
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
    case unpinnedInput(String)
    case provenanceMismatch(String)
    case badPackageName(String)
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
    /// manifest it wrote. Every name is validated before anything is copied, and every
    /// copied file is checked against `provenance` before the manifest can be written, so
    /// `hfProvenanceVerified` is never stamped true on a bundle that has not earned it.
    @discardableResult
    public func build(into root: URL, provenance: Provenance) throws -> RuntimeManifest {
        for name in packages {
            guard Self.isPackageName(name) else { throw BuildError.badPackageName(name) }
        }
        let sortedVoices = voices.sorted()
        for id in sortedVoices {
            guard Self.isVoiceID(id) else { throw BuildError.badVoiceID(id) }
        }
        let pinned = Dictionary(
            provenance.inputs.map { ($0.path, $0) }, uniquingKeysWith: { first, _ in first })

        let fm = FileManager.default
        try? fm.removeItem(at: root)
        for folder in ["coreml", "voices", "runtime"] {
            try fm.createDirectory(at: root.appendingPathComponent(folder), withIntermediateDirectories: true)
        }
        // What this build has already laid out, by the SHA-256 of its bytes: the four
        // buckets differ only in their model.mlmodel, and a second input with the same
        // bytes becomes a hard link to the first so the archive stores them once.
        var placed: [String: URL] = [:]
        var modelPackages: [PackageDigest] = []
        for name in packages {
            let relative = "coreml/\(name).mlpackage"
            let destination = try copy(relative, to: root.appendingPathComponent(relative), reusing: &placed)
            let digest = try Digest.package(at: destination, path: relative)
            for file in digest.files {
                try verify(file, sourcePath: "\(relative)/\(file.path)", against: pinned)
            }
            modelPackages.append(digest)
        }
        var voiceDigests: [FileDigest] = []
        for id in sortedVoices {
            let sourcePath = "kokoro.js/voices/\(id).bin"
            let destination = try copy(
                sourcePath, to: root.appendingPathComponent("voices/\(id).bin"), reusing: &placed)
            let digest = try Digest.file(at: destination, path: "voices/\(id).bin")
            try verify(digest, sourcePath: sourcePath, against: pinned)
            voiceDigests.append(digest)
        }
        var assets: [String: FileDigest] = [:]
        for name in Self.runtimeAssetNames {
            let relative = "runtime/\(name)"
            let destination = try copy(relative, to: root.appendingPathComponent(relative), reusing: &placed)
            let digest = try Digest.file(at: destination, path: relative)
            try verify(digest, sourcePath: relative, against: pinned)
            assets[name] = digest
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

    private func copy(_ relative: String, to destination: URL, reusing placed: inout [String: URL]) throws
        -> URL
    {
        let source = inputs.appendingPathComponent(relative)
        var isDirectory: ObjCBool = false
        guard FileManager.default.fileExists(atPath: source.path, isDirectory: &isDirectory) else {
            throw BuildError.missingInput(relative)
        }
        try FileManager.default.createDirectory(
            at: destination.deletingLastPathComponent(), withIntermediateDirectories: true)
        if isDirectory.boolValue {
            try copyTree(from: source, to: destination, reusing: &placed)
        } else {
            try copyFile(from: source, to: destination, reusing: &placed)
        }
        return destination
    }

    /// A package is a folder, so it is walked in sorted order rather than copied whole:
    /// every file goes through `copyFile`, and the order is fixed so two builds lay the
    /// same inode down first.
    private func copyTree(from source: URL, to destination: URL, reusing placed: inout [String: URL]) throws {
        try FileManager.default.createDirectory(at: destination, withIntermediateDirectories: true)
        for name in try FileManager.default.contentsOfDirectory(atPath: source.path).sorted() {
            let child = source.appendingPathComponent(name)
            var isDirectory: ObjCBool = false
            _ = FileManager.default.fileExists(atPath: child.path, isDirectory: &isDirectory)
            if isDirectory.boolValue {
                try copyTree(from: child, to: destination.appendingPathComponent(name), reusing: &placed)
            } else {
                try copyFile(from: child, to: destination.appendingPathComponent(name), reusing: &placed)
            }
        }
    }

    /// Bytes this build has already laid out are hard-linked rather than copied again,
    /// which is what lets the archive store the buckets' shared weights once. A
    /// filesystem that will not link gets a plain copy, correct but larger.
    private func copyFile(from source: URL, to destination: URL, reusing placed: inout [String: URL]) throws {
        let sha256 = try Digest.sha256(ofFileAt: source)
        if let twin = placed[sha256] {
            do {
                try FileManager.default.linkItem(at: twin, to: destination)
            } catch {
                try FileManager.default.copyItem(at: source, to: destination)
            }
        } else {
            try FileManager.default.copyItem(at: source, to: destination)
        }
        placed[sha256] = destination
    }

    /// A copied file earns its place only if `provenance` has a record for its path under
    /// the inputs folder, and that record's size and hash match what was just digested.
    private func verify(_ digest: FileDigest, sourcePath: String, against pinned: [String: PinnedRecord])
        throws
    {
        guard let record = pinned[sourcePath] else { throw BuildError.unpinnedInput(sourcePath) }
        guard record.bytes == digest.bytes, record.sha256 == digest.sha256 else {
            throw BuildError.provenanceMismatch(sourcePath)
        }
    }

    /// A Kokoro voice id is a language letter, a gender letter, an underscore and a name:
    /// `af_bella`. Anything else is refused before it can become a path.
    static func isVoiceID(_ id: String) -> Bool {
        id.wholeMatch(of: /[ab][fm]_[a-z]+/) != nil
    }

    /// A package name is lowercase letters, digits and underscores: `kokoro_duration_t128`.
    /// Anything else is refused before it can become a path.
    static func isPackageName(_ name: String) -> Bool {
        name.wholeMatch(of: /^[a-z0-9_]+$/) != nil
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
