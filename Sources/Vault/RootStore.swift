import Foundation

/// The vault roots, each held as a security-scoped bookmark in `UserDefaults`.
/// A bookmark that no longer resolves is reported rather than deleted: the folder
/// may be on a volume that is merely unmounted, and the blob is what remembers it.
public final class RootStore {
    public static let key = "vaultRoots"
    private let defaults: UserDefaults
    private var resolved: [URL] = []
    private var accessing: Set<String> = []

    public init(defaults: UserDefaults = .standard) { self.defaults = defaults }

    /// The roots that resolved, and how many did not.
    public struct Load: Sendable, Hashable {
        public var urls: [URL]
        public var unresolved: Int
        public init(urls: [URL], unresolved: Int) {
            self.urls = urls
            self.unresolved = unresolved
        }
    }

    @discardableResult
    public func load() -> Load {
        let blobs = defaults.array(forKey: Self.key) as? [Data] ?? []
        var urls: [URL] = []
        var unresolved = 0
        for data in blobs {
            var stale = false
            guard
                let url = try? URL(
                    resolvingBookmarkData: data, options: .withSecurityScope, bookmarkDataIsStale: &stale)
            else {
                unresolved += 1
                continue
            }
            startAccessing(url)
            urls.append(url)
        }
        resolved = urls
        return Load(urls: urls, unresolved: unresolved)
    }

    /// Bookmark resolution hands back the fully resolved path, so the URL a caller
    /// holds and the one that comes back out of a blob can name the same folder and
    /// still differ as values. Identity is the resolved path.
    private static func key(_ url: URL) -> String { url.resolvingSymlinksInPath().standardizedFileURL.path }

    @discardableResult
    public func add(_ url: URL) -> [URL] {
        guard !resolved.contains(where: { Self.key($0) == Self.key(url) }) else { return resolved }
        guard
            let data = try? url.bookmarkData(
                options: .withSecurityScope, includingResourceValuesForKeys: nil, relativeTo: nil)
        else { return resolved }
        var blobs = defaults.array(forKey: Self.key) as? [Data] ?? []
        blobs.append(data)
        defaults.set(blobs, forKey: Self.key)
        startAccessing(url)
        resolved.append(url)
        return resolved
    }

    public func remove(_ url: URL) {
        let blobs = defaults.array(forKey: Self.key) as? [Data] ?? []
        let keep = blobs.filter { data in
            var stale = false
            guard
                let stored = try? URL(
                    resolvingBookmarkData: data, options: [.withSecurityScope, .withoutUI],
                    bookmarkDataIsStale: &stale)
            else { return true }
            return Self.key(stored) != Self.key(url)
        }
        defaults.set(keep, forKey: Self.key)
        url.stopAccessingSecurityScopedResource()
        accessing.remove(url.path)
        resolved.removeAll { Self.key($0) == Self.key(url) }
    }

    private func startAccessing(_ url: URL) {
        guard !accessing.contains(url.path) else { return }
        _ = url.startAccessingSecurityScopedResource()
        accessing.insert(url.path)
    }
}
