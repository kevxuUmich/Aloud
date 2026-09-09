import Foundation
import Testing

@testable import Vault

@Suite struct ProgressStoreTests {
    @Test func roundTripsThroughDisk() throws {
        let file = FileManager.default.temporaryDirectory.appendingPathComponent(
            UUID().uuidString + ".json")
        let a = ProgressStore(file: file)
        let url = URL(fileURLWithPath: "/tmp/x.md")
        a.set(Progress(sentenceIndex: 12, finished: false, lastPlayed: .now), for: url)
        a.flush()
        let b = ProgressStore(file: file)
        #expect(b.progress(for: url)?.sentenceIndex == 12)
        #expect(b.lastPlayedPath() == "/tmp/x.md")
    }
    @Test func missingFileIsEmpty() {
        let file = FileManager.default.temporaryDirectory.appendingPathComponent(
            UUID().uuidString + ".json")
        #expect(ProgressStore(file: file).progress(for: URL(fileURLWithPath: "/nope")) == nil)
    }
}
