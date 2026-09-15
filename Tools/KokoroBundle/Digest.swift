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
