import Foundation

public actor Extraction {
    struct Key: Hashable {
        let path: String
        let modified: Date
        let options: ExtractOptions
    }
    private var cache: [Key: Script] = [:]
    private(set) var hits = 0

    public init() {}

    public func script(for url: URL, kind: SourceKind, options: ExtractOptions) async throws -> Script {
        // `URL.resourceValues(forKeys:)` caches its result on the URL value, so a
        // second call on the same URL can return a stale modification date; the
        // file manager's attributes are read fresh each time.
        let attributes = try FileManager.default.attributesOfItem(atPath: url.path)
        let modified = (attributes[.modificationDate] as? Date) ?? .distantPast
        let key = Key(path: url.path, modified: modified, options: options)
        if let hit = cache[key] {
            hits += 1
            return hit
        }
        let data = try Data(contentsOf: url)
        let script = try Extractors.extractor(for: kind).script(from: data, options: options)
        cache = cache.filter { $0.key.path != url.path }
        cache[key] = script
        return script
    }

    public func invalidate(_ url: URL) {
        cache = cache.filter { $0.key.path != url.path }
    }
}
