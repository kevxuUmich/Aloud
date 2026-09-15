import Foundation

/// Where the model lives. Both roots are the app's own folders, under the `Aloud`
/// folder the progress file already uses, so no file entitlement changes; in the
/// sandboxed build they resolve inside the container.
public struct KokoroPaths: Sendable {
    public let support: URL
    public let caches: URL

    public init(support: URL, caches: URL) {
        self.support = support
        self.caches = caches
    }

    public static func standard() -> KokoroPaths {
        let fm = FileManager.default
        let support = fm.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("Aloud/Kokoro", isDirectory: true)
        let caches = fm.urls(for: .cachesDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("Aloud/Kokoro", isDirectory: true)
        return KokoroPaths(support: support, caches: caches)
    }

    /// The installed bundle: the SDK's manifest at its root.
    public func modelDirectory(version: String) -> URL {
        support.appendingPathComponent(version, isDirectory: true)
    }
    /// Written last, so a folder without it is a crash mid-install to be swept away.
    public func marker(version: String) -> URL {
        modelDirectory(version: version).appendingPathComponent(".complete")
    }
    /// The compiled CoreML models, excluded from backup; removed with the version.
    public func compiledCache(version: String) -> URL {
        caches.appendingPathComponent(version, isDirectory: true)
    }
    /// What a dropped connection leaves behind for the next attempt to continue from.
    public var resumeData: URL { support.appendingPathComponent("resume.data") }
    /// Where a finished download waits for its checksum.
    public var archive: URL { support.appendingPathComponent("download.aar") }
    /// Where an archive is extracted before it is moved into place whole.
    public var installing: URL { support.appendingPathComponent(".installing", isDirectory: true) }
}
