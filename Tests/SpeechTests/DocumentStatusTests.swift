import Foundation
import Testing
import Vault

@testable import Speech

@Suite struct DocumentStatusTests {
    func label(
        progress: PlaybackProgress? = nil, isCurrent: Bool = false, remaining: Duration? = nil,
        previewWords: Int = 0, bytes: Int = 0, rateFactor: Double = 1
    ) -> String {
        DocumentStatus.label(
            progress: progress, isCurrent: isCurrent, remaining: remaining, previewWords: previewWords,
            bytes: bytes, rateFactor: rateFactor)
    }
    func started(at i: Int, finished: Bool = false) -> PlaybackProgress {
        PlaybackProgress(sentenceIndex: i, finished: finished, lastPlayed: .now)
    }

    @Test func finishedWins() {
        let l = label(
            progress: started(at: 40, finished: true), isCurrent: true, remaining: .seconds(90))
        #expect(l == "Finished")
    }
    @Test func theCurrentDocumentCountsDown() {
        #expect(label(progress: started(at: 3), isCurrent: true, remaining: .seconds(192)) == "3:12 left")
    }
    @Test func anotherStartedDocumentIsInProgress() {
        #expect(label(progress: started(at: 3), isCurrent: false, remaining: .seconds(192)) == "In progress")
    }
    @Test func theCurrentDocumentWithoutAClockIsInProgress() {
        #expect(label(progress: started(at: 3), isCurrent: true, remaining: nil) == "In progress")
    }
    @Test func anUnstartedDocumentIsAnEstimate() {
        // 160 words is one minute at 1x, and 1920 bytes is 320 words at six bytes each.
        #expect(label(previewWords: 160) == "~1 min")
        #expect(label(previewWords: 10, bytes: 1920) == "~2 min")
        #expect(label(previewWords: 160, rateFactor: 2) == "~1 min")
        #expect(label(previewWords: 1600, rateFactor: 2) == "~5 min")
    }
    @Test func aDocumentAtIndexZeroIsStillAnEstimate() {
        let l = label(
            progress: started(at: 0), isCurrent: true, remaining: .seconds(60), previewWords: 160)
        #expect(l == "~1 min")
    }
    @Test func noWordsIsNoStatus() {
        #expect(label() == "")
        #expect(label(bytes: 5) == "")
    }
}
