import Foundation

public struct Progress: Codable, Hashable, Sendable {
    public var sentenceIndex: Int
    public var finished: Bool
    public var lastPlayed: Date
    public init(sentenceIndex: Int, finished: Bool, lastPlayed: Date) {
        self.sentenceIndex = sentenceIndex
        self.finished = finished
        self.lastPlayed = lastPlayed
    }
}

public final class ProgressStore: @unchecked Sendable {
    private let file: URL
    private let lock = NSLock()
    private var table: [String: Progress]
    private var pending: DispatchWorkItem?
    public static let debounce: TimeInterval = 1

    public init(file: URL) {
        self.file = file
        if let data = try? Data(contentsOf: file),
            let t = try? JSONDecoder().decode([String: Progress].self, from: data)
        {
            table = t
        } else {
            table = [:]
        }
    }

    public static func standard() -> ProgressStore {
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("Aloud", isDirectory: true)
        try? FileManager.default.createDirectory(at: base, withIntermediateDirectories: true)
        return ProgressStore(file: base.appendingPathComponent("progress.json"))
    }

    public func progress(for url: URL) -> Progress? { lock.withLock { table[url.path] } }

    public func set(_ p: Progress, for url: URL) {
        lock.withLock { table[url.path] = p }
        scheduleWrite()
    }

    public func lastPlayedPath() -> String? {
        lock.withLock { table.max { $0.value.lastPlayed < $1.value.lastPlayed }?.key }
    }

    private func scheduleWrite() {
        let item = DispatchWorkItem { [weak self] in self?.flush() }
        lock.withLock {
            pending?.cancel()
            pending = item
        }
        DispatchQueue.global(qos: .utility).asyncAfter(deadline: .now() + Self.debounce, execute: item)
    }

    public func flush() {
        let snapshot = lock.withLock { table }
        if let data = try? JSONEncoder().encode(snapshot) { try? data.write(to: file, options: .atomic) }
    }
}
