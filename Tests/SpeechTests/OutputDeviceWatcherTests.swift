import Foundation
import Testing

@testable import Speech

@Suite struct OutputDeviceWatcherTests {
    /// The default output device cannot be changed from a test, so what is testable
    /// here is that the listener registers, and that stopping twice is safe.
    @Test func constructsAndStopsTwiceWithoutCrashing() async throws {
        let watcher = OutputDeviceWatcher {}
        try await Task.sleep(for: .milliseconds(100))
        watcher.stop()
        watcher.stop()
    }
}
