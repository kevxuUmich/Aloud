import CoreServices
import Foundation

/// Recursive folder watching through FSEvents. `onChange` is called on a private queue,
/// coalesced by `latency`, once per burst of changes.
public final class FolderWatcher: @unchecked Sendable {
    private var stream: FSEventStreamRef?
    private let queue = DispatchQueue(label: "design.kevxu.aloud.watcher")
    private let onChange: @Sendable () -> Void

    public init(paths: [URL], latency: TimeInterval = 0.3, onChange: @escaping @Sendable () -> Void) {
        self.onChange = onChange
        var context = FSEventStreamContext(
            version: 0, info: Unmanaged.passUnretained(self).toOpaque(),
            retain: nil, release: nil, copyDescription: nil)
        let callback: FSEventStreamCallback = { _, info, _, _, _, _ in
            guard let info else { return }
            Unmanaged<FolderWatcher>.fromOpaque(info).takeUnretainedValue().onChange()
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
        guard let s = stream else { return }
        FSEventStreamStop(s)
        FSEventStreamInvalidate(s)
        FSEventStreamRelease(s)
        stream = nil
    }

    deinit { stop() }
}
