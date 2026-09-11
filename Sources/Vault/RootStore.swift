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
    /// arrays stay the same length even when a migration has nothing to fill from. It
    /// is for display only: identity is the index, so two of these naming one folder
    /// each is a legible list and not a collision.
    static func unknownPath(_ index: Int) -> String { "Folder \(index + 1)" }
    private let defaults: UserDefaults
    private var resolved: [URL] = []
    private var accessing: Set<String> = []

    public init(defaults: UserDefaults = .standard) { self.defaults = defaults }

    /// A root whose bookmark will not resolve. Identity is the blob's index in the
    /// stored array, never its path: a store migrated from before the paths array
    /// existed can hand two broken roots the same placeholder, and a list keyed by that
    /// would show one row for two folders and locate the wrong one.
    public struct UnreachableRoot: Identifiable, Hashable, Sendable {
        public let index: Int
        public let path: String
        public var id: Int { index }
        public init(index: Int, path: String) {
            self.index = index
            self.path = path
        }
    }

    /// The roots that resolved, how many did not, and where in the stored array each of
    /// those sits with the last known path that names it in Settings.
    public struct Load: Sendable, Hashable {
        public var urls: [URL]
        public var unresolved: Int
        public var unreachable: [UnreachableRoot]
        public init(urls: [URL], unresolved: Int, unreachable: [UnreachableRoot] = []) {
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
        var unreachable: [UnreachableRoot] = []
        for (i, data) in blobs.enumerated() {
            guard let url = Self.resolve(data) else {
                unreachable.append(UnreachableRoot(index: i, path: paths[i]))
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
        // will not resolve is not this method's business: it has no URL to be named by,
        // and `remove(unreachableIndex:)` is what removes it.
        let drop = Set(
            blobs.indices.filter { Self.resolve(blobs[$0]).map(Self.key) == Self.key(url) })
        write(blobs: blobs, paths: paths, dropping: drop)
        url.stopAccessingSecurityScopedResource()
        accessing.remove(Self.key(url))
        resolved.removeAll { Self.key($0) == Self.key(url) }
    }

    /// Settings' Detach Folder on a root that will not resolve, addressed by its index in the
    /// stored array because a placeholder path names nothing.
    public func remove(unreachableIndex index: Int) {
        let blobs = defaults.array(forKey: Self.key) as? [Data] ?? []
        guard blobs.indices.contains(index) else { return }
        write(blobs: blobs, paths: storedPaths(matching: blobs), dropping: [index])
    }

    private func write(blobs: [Data], paths: [String], dropping drop: Set<Int>) {
        defaults.set(blobs.indices.filter { !drop.contains($0) }.map { blobs[$0] }, forKey: Self.key)
        defaults.set(
            paths.indices.filter { !drop.contains($0) }.map { paths[$0] }, forKey: Self.pathsKey)
    }

    /// Locate: the folder behind an unreachable bookmark is pointed at again, and the
    /// new bookmark takes the old one's place rather than being appended, so the root
    /// keeps its position in the list. Addressed by index for the reason
    /// `UnreachableRoot` is.
    ///
    /// Locating onto a folder that is already a root is not a replacement but an
    /// answer: the two entries were always the same folder. The broken one is dropped
    /// rather than written over, which would leave two blobs for one path - the
    /// duplicate `add` has always refused.
    public func replace(unreachableIndex index: Int, with url: URL) {
        var blobs = defaults.array(forKey: Self.key) as? [Data] ?? []
        var paths = storedPaths(matching: blobs)
        guard blobs.indices.contains(index) else { return }
        let alreadyARoot =
            resolved.contains { Self.key($0) == Self.key(url) }
            || blobs.indices.contains {
                $0 != index && Self.resolve(blobs[$0]).map(Self.key) == Self.key(url)
            }
        guard !alreadyARoot else {
            write(blobs: blobs, paths: paths, dropping: [index])
            return
        }
        guard let data = Self.bookmark(url) else { return }
        blobs[index] = data
        paths[index] = Self.key(url)
        defaults.set(blobs, forKey: Self.key)
        defaults.set(paths, forKey: Self.pathsKey)
        startAccessing(url)
        resolved.append(url)
    }

    /// The paths array as it must be to sit beside these blobs: what is stored, when
    /// that is already parallel, and otherwise a migration. A store written before the
    /// array existed has none, so each blob it is short by is asked for its path once,
    /// and the ones that will not resolve are given a placeholder - they have no name
    /// to give, and something has to keep the index arithmetic honest.
    private func storedPaths(matching blobs: [Data]) -> [String] {
        var paths = defaults.array(forKey: Self.pathsKey) as? [String] ?? []
        if paths.count > blobs.count { paths = Array(paths.prefix(blobs.count)) }
        while paths.count < blobs.count {
            let i = paths.count
            paths.append(Self.resolve(blobs[i]).map(Self.key) ?? Self.unknownPath(i))
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
