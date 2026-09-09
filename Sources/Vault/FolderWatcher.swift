import CoreServices
import Foundation

/// Recursive folder watching through FSEvents. `onChange` is called on a private queue,
/// coalesced by `latency`, once per burst of changes.
///
/// `stop()` runs its teardown synchronously on the same queue the stream is scheduled on
/// (`FSEventStreamInvalidate` requires that), and `isStopped` is only ever read or written
/// while on that queue - by `stop()` itself and by the FSEvents callback, which macOS always
/// runs on `queue` because of `FSEventStreamSetDispatchQueue`. That serializes the two, so a
/// callback already in flight when `stop()` is called from another thread either finishes
/// first or never observes a half-torn-down stream. A `DispatchSpecificKey` lets `stop()`
/// detect it is already running on `queue` - which happens when `onChange` itself calls
/// `stop()` - and run its work inline instead of calling `queue.sync`, which would deadlock.
public final class FolderWatcher: @unchecked Sendable {
    private var stream: FSEventStreamRef?
    private let queue = DispatchQueue(label: "design.kevxu.aloud.watcher")
    private let onChange: @Sendable () -> Void
    private var isStopped = false
    private static let queueKey = DispatchSpecificKey<Void>()

    public init(paths: [URL], latency: TimeInterval = 0.3, onChange: @escaping @Sendable () -> Void) {
        self.onChange = onChange
        queue.setSpecific(key: Self.queueKey, value: ())
        var context = FSEventStreamContext(
            version: 0, info: Unmanaged.passUnretained(self).toOpaque(),
            retain: nil, release: nil, copyDescription: nil)
        let callback: FSEventStreamCallback = { _, info, _, _, _, _ in
            guard let info else { return }
            let watcher = Unmanaged<FolderWatcher>.fromOpaque(info).takeUnretainedValue()
            // Runs on `queue`, same as `stop()`'s teardown, so this read of `isStopped`
            // never races its write.
            guard !watcher.isStopped else { return }
            watcher.onChange()
        }
        let flags = UInt32(
            kFSEventStreamCreateFlagFileEvents | kFSEventStreamCreateFlagNoDefer
                | kFSEventStreamCreateFlagUseCFTypes)
        guard
            let s = FSEventStreamCreate(
                nil, callback, &context, paths.map(\.path) as CFArray,
                FSEventStreamEventId(kFSEventStreamEventIdSinceNow), latency, flags)
        else { return }
        stream = s
        FSEventStreamSetDispatchQueue(s, queue)
        FSEventStreamStart(s)
    }

    public func stop() {
        let teardown = {
            guard !self.isStopped, let s = self.stream else { return }
            self.isStopped = true
            FSEventStreamStop(s)
            FSEventStreamInvalidate(s)
            FSEventStreamRelease(s)
            self.stream = nil
        }
        if DispatchQueue.getSpecific(key: Self.queueKey) != nil {
            teardown()
        } else {
            queue.sync(execute: teardown)
        }
    }

    deinit { stop() }
}
