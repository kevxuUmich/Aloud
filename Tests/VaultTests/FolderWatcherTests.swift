import Foundation
import Testing

@testable import Vault

@Suite struct FolderWatcherTests {
    @Test func firesOnceForANestedWrite() async throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
            .resolvingSymlinksInPath()
        let nested = root.appendingPathComponent("deep/er")
        try FileManager.default.createDirectory(at: nested, withIntermediateDirectories: true)
        let fired = Fired()
        let watcher = FolderWatcher(paths: [root], latency: 0.2) { fired.bump() }
        defer { watcher.stop() }
        try await Task.sleep(for: .milliseconds(300))
        try "a".write(to: nested.appendingPathComponent("a.md"), atomically: true, encoding: .utf8)
        try "b".write(to: nested.appendingPathComponent("b.md"), atomically: true, encoding: .utf8)
        try await Task.sleep(for: .seconds(2))
        #expect(fired.count >= 1)
        #expect(fired.count <= 2)
    }

    @Test func stopTwiceDoesNotCrash() async throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
            .resolvingSymlinksInPath()
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        let watcher = FolderWatcher(paths: [root], latency: 0.1) {}
        watcher.stop()
        watcher.stop()
    }

    @Test func stopFromWithinTheCallbackDoesNotDeadlock() async throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
            .resolvingSymlinksInPath()
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        let box = WatcherBox()
        let fired = Fired()
        box.watcher = FolderWatcher(paths: [root], latency: 0.1) {
            fired.bump()
            box.watcher?.stop()
        }
        try await Task.sleep(for: .milliseconds(300))
        try "a".write(to: root.appendingPathComponent("a.md"), atomically: true, encoding: .utf8)
        try await Task.sleep(for: .seconds(1))
        #expect(fired.count == 1)
    }
}

final class WatcherBox: @unchecked Sendable {
    var watcher: FolderWatcher?
}

final class Fired: @unchecked Sendable {
    private let lock = NSLock()
    private var n = 0
    var count: Int { lock.withLock { n } }
    func bump() { lock.withLock { n += 1 } }
}
