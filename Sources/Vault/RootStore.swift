import Foundation

/// The vault roots, each held as a security-scoped bookmark in `UserDefaults`.
/// A bookmark that no longer resolves is reported rather than deleted: the folder
/// may be on a volume that is merely unmounted, and the blob is what remembers it.
///
/// Beside the blobs is a parallel array of the paths they last resolved to, which is
/// the only way an unreachable root can be named: a blob that will not resolve has no
/// URL to ask, so a folder that is merely unmounted would otherwise show in Settings as
/// nothing at all. The two arrays are written together and are the same length by
/// construction.
public final class RootStore {
    public static let key = "vaultRoots"
    public static let pathsKey = "vaultRootPaths"
    /// What a path that cannot be recovered from its blob is recorded as, so the two
    /// arrays stay the same length even when a migration has nothing to fill from.
    static let unknownPath = "?"
    private let defaults: UserDefaults
    private var resolved: [URL] = []
    private var accessing: Set<String> = []

    public init(defaults: UserDefaults = .standard) { self.defaults = defaults }

    /// The roots that resolved, how many did not, and the last known path of each of
    /// those, which is what names them in Settings.
    public struct Load: Sendable, Hashable {
        public var urls: [URL]
        public var unresolved: Int
        public var unreachable: [String]
        public init(urls: [URL], unresolved: Int, unreachable: [String] = []) {
            self.urls = urls
            self.unresolved = unresolved
            self.unreachable = unreachable
        }
    }

    @discardableResult
    public func load() -> Load {
        let blobs = defaults.array(forKey: Self.key) as? [Data] ?? []
        var paths = storedPaths(matching: blobs)
        var urls: [URL] = []
        var unreachable: [String] = []
        for (i, data) in blobs.enumerated() {
            guard let url = Self.resolve(data) else {
                unreachable.append(paths[i])
                continue
            }
            startAccessing(url)
            // Resolution is also the one moment the recorded path can be refreshed: a
            // bookmark follows a folder that was moved, and the name Settings shows
            // should follow it too.
            paths[i] = Self.key(url)
            urls.append(url)
        }
        defaults.set(paths, forKey: Self.pathsKey)
        resolved = urls
        return Load(urls: urls, unresolved: unreachable.count, unreachable: unreachable)
    }

    /// Bookmark resolution hands back the fully resolved path, so the URL a caller
    /// holds and the one that comes back out of a blob can name the same folder and
    /// still differ as values. Identity is the resolved path.
    public static func key(_ url: URL) -> String {
        url.resolvingSymlinksInPath().standardizedFileURL.path
    }

    @discardableResult
    public func add(_ url: URL) -> [URL] {
        guard !resolved.contains(where: { Self.key($0) == Self.key(url) }) else { return resolved }
        guard let data = Self.bookmark(url) else { return resolved }
        var blobs = defaults.array(forKey: Self.key) as? [Data] ?? []
        var paths = storedPaths(matching: blobs)
        blobs.append(data)
        paths.append(Self.key(url))
        defaults.set(blobs, forKey: Self.key)
        defaults.set(paths, forKey: Self.pathsKey)
        startAccessing(url)
        resolved.append(url)
        return resolved
    }

    public func remove(_ url: URL) {
        let blobs = defaults.array(forKey: Self.key) as? [Data] ?? []
        let paths = storedPaths(matching: blobs)
        // Chosen by index and applied to both arrays, so the blob and the path that
        // describe one root can never be dropped apart from each other. A blob that
        // will not resolve is matched on its recorded path instead, which is what lets
        // an unreachable root be removed rather than only located.
        let drop = Set(
            blobs.indices.filter { i in
                if let stored = Self.resolve(blobs[i]) { return Self.key(stored) == Self.key(url) }
                return paths[i] == Self.key(url)
            })
        defaults.set(blobs.indices.filter { !drop.contains($0) }.map { blobs[$0] }, forKey: Self.key)
        defaults.set(
            paths.indices.filter { !drop.contains($0) }.map { paths[$0] }, forKey: Self.pathsKey)
        url.stopAccessingSecurityScopedResource()
        accessing.remove(Self.key(url))
        resolved.removeAll { Self.key($0) == Self.key(url) }
    }

    /// Locate: the folder behind an unreachable path is pointed at again, and the new
    /// bookmark takes the old one's place rather than being appended, so the root keeps
    /// its position in the list.
    public func replace(unreachablePath: String, with url: URL) {
        var blobs = defaults.array(forKey: Self.key) as? [Data] ?? []
        var paths = storedPaths(matching: blobs)
        guard let i = paths.firstIndex(of: unreachablePath), let data = Self.bookmark(url) else {
            return
        }
        blobs[i] = data
        paths[i] = Self.key(url)
        defaults.set(blobs, forKey: Self.key)
        defaults.set(paths, forKey: Self.pathsKey)
        startAccessing(url)
        if !resolved.contains(where: { Self.key($0) == Self.key(url) }) { resolved.append(url) }
    }

    /// The paths array as it must be to sit beside these blobs: what is stored, when
    /// that is already parallel, and otherwise a migration. A store written before the
    /// array existed has none, so each blob it is short by is asked for its path once,
    /// and the ones that will not resolve are recorded as unknown - they have no name
    /// to give, and a placeholder is what keeps the index arithmetic honest.
    private func storedPaths(matching blobs: [Data]) -> [String] {
        var paths = defaults.array(forKey: Self.pathsKey) as? [String] ?? []
        if paths.count > blobs.count { paths = Array(paths.prefix(blobs.count)) }
        while paths.count < blobs.count {
            paths.append(Self.resolve(blobs[paths.count]).map(Self.key) ?? Self.unknownPath)
        }
        return paths
    }

    /// `withoutUI` throughout: a root on an unmounted volume is Settings' business now,
    /// which offers Locate, rather than the system's to put a panel up over the app.
    private static func resolve(_ data: Data) -> URL? {
        var stale = false
        return try? URL(
            resolvingBookmarkData: data, options: [.withSecurityScope, .withoutUI],
            bookmarkDataIsStale: &stale)
    }

    private static func bookmark(_ url: URL) -> Data? {
        try? url.bookmarkData(
            options: .withSecurityScope, includingResourceValuesForKeys: nil, relativeTo: nil)
    }

    private func startAccessing(_ url: URL) {
        // Keyed the same way identity is, or the same folder reached by two spellings
        // takes two scoped accesses and gives back one.
        guard !accessing.contains(Self.key(url)) else { return }
        _ = url.startAccessingSecurityScopedResource()
        accessing.insert(Self.key(url))
    }
}
