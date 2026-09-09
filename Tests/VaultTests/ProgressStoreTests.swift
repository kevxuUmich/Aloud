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
    @Test func concurrentSetsDoNotCrash() async throws {
        let file = FileManager.default.temporaryDirectory.appendingPathComponent(
            UUID().uuidString + ".json")
        let store = ProgressStore(file: file)
        await withTaskGroup(of: Void.self) { group in
            for i in 0..<50 {
                group.addTask {
                    store.set(
                        Progress(sentenceIndex: i, finished: false, lastPlayed: .now),
                        for: URL(fileURLWithPath: "/tmp/\(i).md"))
                }
            }
        }
        store.flush()
        let reloaded = ProgressStore(file: file)
        let found = (0..<50).filter {
            reloaded.progress(for: URL(fileURLWithPath: "/tmp/\($0).md")) != nil
        }
        #expect(found.count == 50)
    }
}
