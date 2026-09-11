import Foundation

public struct PlaybackProgress: Codable, Hashable, Sendable {
    public var sentenceIndex: Int
    public var finished: Bool
    public var lastPlayed: Date
    /// The reader's own flag on the document, kept beside the place so it lives in
    /// Aloud's data and never in the file. A file written before there were
    /// bookmarks decodes with it off.
    public var bookmarked: Bool
    public init(sentenceIndex: Int, finished: Bool, lastPlayed: Date, bookmarked: Bool = false) {
        self.sentenceIndex = sentenceIndex
        self.finished = finished
        self.lastPlayed = lastPlayed
        self.bookmarked = bookmarked
    }

    public init(from decoder: any Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        sentenceIndex = try c.decode(Int.self, forKey: .sentenceIndex)
        finished = try c.decode(Bool.self, forKey: .finished)
        lastPlayed = try c.decode(Date.self, forKey: .lastPlayed)
        bookmarked = try c.decodeIfPresent(Bool.self, forKey: .bookmarked) ?? false
    }
}

public final class ProgressStore: @unchecked Sendable {
    private let file: URL
    private let lock = NSLock()
    private var table: [String: PlaybackProgress]
    private var pending: DispatchWorkItem?
    private var lastWrite: Date
    /// The trailing debounce: a burst of sets writes once, a moment after the last one.
    public static let debounce: TimeInterval = 1
    /// The ceiling on that debounce. A steady stream of sets spaced under `debounce`
    /// would otherwise reschedule forever and never write, so a set this long after
    /// the last write flushes now instead of rescheduling.
    public static let maxWait: TimeInterval = 5
    private let maxWaitInterval: TimeInterval

    public init(file: URL, maxWait: TimeInterval = ProgressStore.maxWait) {
        self.file = file
        self.maxWaitInterval = maxWait
        self.lastWrite = Date()
        if let data = try? Data(contentsOf: file),
            let t = try? JSONDecoder().decode([String: PlaybackProgress].self, from: data)
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

    public func progress(for url: URL) -> PlaybackProgress? { lock.withLock { table[url.path] } }

    public func set(_ p: PlaybackProgress, for url: URL) {
        lock.withLock { table[url.path] = p }
        scheduleWrite()
    }

    /// A renamed file keeps its place: the entry under the old path becomes the entry
    /// under the new one. Nothing under the old path is a no-op.
    public func move(from old: URL, to new: URL) {
        let moved = lock.withLock { () -> Bool in
            guard let p = table.removeValue(forKey: old.path) else { return false }
            table[new.path] = p
            return true
        }
        if moved { scheduleWrite() }
    }

    public func lastPlayedPath() -> String? {
        lock.withLock { table.max { $0.value.lastPlayed < $1.value.lastPlayed }?.key }
    }

    private func scheduleWrite() {
        let starved = lock.withLock { Date().timeIntervalSince(lastWrite) > maxWaitInterval }
        if starved {
            lock.withLock {
                pending?.cancel()
                pending = nil
            }
            flush()
            return
        }
        let item = DispatchWorkItem { [weak self] in self?.flush() }
        lock.withLock {
            pending?.cancel()
            pending = item
        }
        DispatchQueue.global(qos: .utility).asyncAfter(deadline: .now() + Self.debounce, execute: item)
    }

    public func flush() {
        let snapshot = lock.withLock { () -> [String: PlaybackProgress] in
            lastWrite = Date()
            return table
        }
        if let data = try? JSONEncoder().encode(snapshot) { try? data.write(to: file, options: .atomic) }
    }
}
