import Foundation

/// Everything the download is pinned by. Bumping the bundle is a change to these values
/// and a new release asset; nothing else in the app knows a version.
public struct KokoroReleaseInfo: Sendable, Equatable {
    public let url: URL
    public let version: String
    public let sha256: String
    public let bytes: Int64
    public init(url: URL, version: String, sha256: String, bytes: Int64) {
        self.url = url
        self.version = version
        self.sha256 = sha256
        self.bytes = bytes
    }
    /// The size as the picker's badge shows it, in whole megabytes.
    public var sizeLabel: String { KokoroRelease.megabytes(bytes) }
}

public enum KokoroRelease {
    /// Whole megabytes, as the picker's badge and the Settings row both say it. One
    /// place, so the two can never round differently, and the only place the divisor
    /// lives: `Sources/Aloud` carries no number literal of its own.
    public static func megabytes(_ bytes: Int64) -> String { "\(bytes / 1_000_000) MB" }

    public static let current = KokoroReleaseInfo(
        url: URL(string: "https://github.com/kevxuUmich/Aloud/releases/download/kokoro-models/kokoro-2.aar")!,
        version: "2",
        sha256: "4744918f3af59e4ed031b763c698e91d6eb424fd5027982e85ca1cc6a527b15e",
        bytes: 159_343_644)
}
