import Foundation

final class RootStore {
    static let key = "vaultRoots"
    private let defaults: UserDefaults
    private var resolved: [URL] = []
    private var accessing: Set<String> = []

    init(defaults: UserDefaults = .standard) { self.defaults = defaults }

    func load() -> [URL] {
        let blobs = defaults.array(forKey: Self.key) as? [Data] ?? []
        resolved = blobs.compactMap { data in
            var stale = false
            guard
                let url = try? URL(
                    resolvingBookmarkData: data, options: .withSecurityScope, bookmarkDataIsStale: &stale)
            else { return nil }
            startAccessing(url)
            return url
        }
        return resolved
    }

    @discardableResult
    func add(_ url: URL) -> [URL] {
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

    func remove(_ url: URL) {
        let blobs = defaults.array(forKey: Self.key) as? [Data] ?? []
        let keep = blobs.filter { data in
            var stale = false
            guard
                let stored = try? URL(
                    resolvingBookmarkData: data, options: [.withSecurityScope, .withoutUI],
                    bookmarkDataIsStale: &stale)
            else { return true }
            return stored != url
        }
        defaults.set(keep, forKey: Self.key)
        url.stopAccessingSecurityScopedResource()
        accessing.remove(url.path)
        resolved.removeAll { $0 == url }
    }

    private func startAccessing(_ url: URL) {
        guard !accessing.contains(url.path) else { return }
        _ = url.startAccessingSecurityScopedResource()
        accessing.insert(url.path)
    }
}
