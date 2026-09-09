import Foundation

final class RootStore {
    static let key = "vaultRoots"
    private let defaults: UserDefaults
    init(defaults: UserDefaults = .standard) { self.defaults = defaults }

    func load() -> [URL] {
        let blobs = defaults.array(forKey: Self.key) as? [Data] ?? []
        return blobs.compactMap { data in
            var stale = false
            guard
                let url = try? URL(
                    resolvingBookmarkData: data, options: .withSecurityScope, bookmarkDataIsStale: &stale)
            else { return nil }
            _ = url.startAccessingSecurityScopedResource()
            return url
        }
    }

    func add(_ url: URL) {
        guard
            let data = try? url.bookmarkData(
                options: .withSecurityScope, includingResourceValuesForKeys: nil, relativeTo: nil)
        else { return }
        var blobs = defaults.array(forKey: Self.key) as? [Data] ?? []
        blobs.append(data)
        defaults.set(blobs, forKey: Self.key)
    }

    func remove(_ url: URL) {
        let keep = load().filter { $0 != url }
        defaults.removeObject(forKey: Self.key)
        keep.forEach(add)
    }
}
