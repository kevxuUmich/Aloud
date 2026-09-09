import Foundation
import Testing

@testable import Vault

@Suite struct ProgressStoreTests {
    @Test func roundTripsThroughDisk() throws {
        let file = FileManager.default.temporaryDirectory.appendingPathComponent(
            UUID().uuidString + ".json")
        let a = ProgressStore(file: file)
        let url = URL(fileURLWithPath: "/tmp/x.md")
        a.set(PlaybackProgress(sentenceIndex: 12, finished: false, lastPlayed: .now), for: url)
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
    @Test func aSetPastTheMaxWaitWritesWithoutWaitingForTheDebounce() throws {
        let file = FileManager.default.temporaryDirectory.appendingPathComponent(
            UUID().uuidString + ".json")
        let store = ProgressStore(file: file, maxWait: 0)
        let url = URL(fileURLWithPath: "/tmp/starved.md")
        store.set(PlaybackProgress(sentenceIndex: 1, finished: false, lastPlayed: .now), for: url)
        store.set(PlaybackProgress(sentenceIndex: 2, finished: false, lastPlayed: .now), for: url)
        let data = try Data(contentsOf: file)
        let table = try JSONDecoder().decode([String: PlaybackProgress].self, from: data)
        #expect(table[url.path]?.sentenceIndex == 2)
    }
    @Test func concurrentSetsDoNotCrash() async throws {
        let file = FileManager.default.temporaryDirectory.appendingPathComponent(
            UUID().uuidString + ".json")
        let store = ProgressStore(file: file)
        await withTaskGroup(of: Void.self) { group in
            for i in 0..<50 {
                group.addTask {
                    store.set(
                        PlaybackProgress(sentenceIndex: i, finished: false, lastPlayed: .now),
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
