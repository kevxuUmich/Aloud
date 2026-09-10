import AppKit
import Foundation
import Prose
import Testing

@testable import Speech

@Suite @MainActor struct NowPlayingTests {
    final class FakeCenter: NowPlayingCenter {
        var info: [String: Any] = [:]
        var playing: Bool?
        func set(info: [String: Any]) { self.info = info }
        func set(playing: Bool) { self.playing = playing }
    }
    final class FakeCommands: RemoteCommands {
        var play: (@MainActor () -> Void)?
        var pause: (@MainActor () -> Void)?
        var toggle: (@MainActor () -> Void)?
        var forward: (@MainActor () -> Void)?
        var backward: (@MainActor () -> Void)?
        func bind(
            play: @escaping @Sendable @MainActor () -> Void,
            pause: @escaping @Sendable @MainActor () -> Void,
            toggle: @escaping @Sendable @MainActor () -> Void,
            skipForward: @escaping @Sendable @MainActor () -> Void,
            skipBackward: @escaping @Sendable @MainActor () -> Void
        ) {
            self.play = play
            self.pause = pause
            self.toggle = toggle
            self.forward = skipForward
            self.backward = skipBackward
        }
    }
    @Test func mirrorsTitleAndStateAndAnswersCommands() {
        let fake = FakeVoiceProvider()
        let p = Player(provider: fake)
        let src = "One two three. Four five six."
        p.load(Script(source: src, sentences: SentenceSplitter.split(src)), at: 0)
        let center = FakeCenter()
        let commands = FakeCommands()
        let np = NowPlaying(player: p, center: center, commands: commands)
        np.update(title: "Essay", subtitle: nil)
        #expect(center.info["title"] as? String == "Essay")
        commands.play?()
        #expect(p.isPlaying)
        #expect(center.playing == true)
        commands.pause?()
        #expect(!p.isPlaying)
        #expect(center.playing == false)
        commands.forward?()
        #expect(p.sentenceIndex == 1)
    }
    /// The card has a subtitle line and a plate, and both are the app's to fill.
    @Test func pushesTheSubtitleAndTheArtwork() {
        let p = Player(provider: FakeVoiceProvider())
        let center = FakeCenter()
        let art = NSImage(size: NSSize(width: 1, height: 1))
        let np = NowPlaying(player: p, artwork: art, center: center, commands: FakeCommands())
        np.update(title: "Essay", subtitle: "Essays")
        #expect(center.info["title"] as? String == "Essay")
        #expect(center.info["subtitle"] as? String == "Essays")
        #expect(center.info["artwork"] as? NSImage === art)
        np.update(title: nil, subtitle: nil)
        #expect(center.info["title"] as? String == "Aloud")
        #expect(center.info["subtitle"] == nil)
        // The plate is the app's for the whole session: a document that clears the
        // title and the subtitle must not clear the picture with them.
        #expect(center.info["artwork"] as? NSImage === art)
    }
    /// The observation and the release below both land on their own schedule, so the
    /// suite waits for the condition rather than for a fixed sleep, which is either
    /// longer than it needs to be or, on a loaded machine, not long enough.
    func poll(until condition: () -> Bool) async throws {
        let deadline = ContinuousClock.now + .seconds(1)
        while ContinuousClock.now < deadline {
            if condition() { return }
            try await Task.sleep(for: .milliseconds(10))
        }
    }

    /// The observation is what makes the panel keep up with the player without anyone
    /// calling `update`. Loading a longer script changes the timeline, and the pushed
    /// duration has to follow it.
    @Test func aLoadPushesTheNewDuration() async throws {
        let fake = FakeVoiceProvider()
        let p = Player(provider: fake)
        let center = FakeCenter()
        let np = NowPlaying(player: p, center: center, commands: FakeCommands())
        np.update(title: "Essay", subtitle: nil)
        let src = "One two three. Four five six. Seven eight nine."
        p.load(Script(source: src, sentences: SentenceSplitter.split(src)), at: 0)
        try await poll { center.info["duration"] as? Double == p.timeline.total.seconds }
        #expect(center.info["duration"] as? Double == p.timeline.total.seconds)
        #expect((center.info["duration"] as? Double ?? 0) > 0)
    }
    /// The first form of the observation held `self` across every suspension, so the
    /// object could never be freed and the task it owned could never be cancelled.
    @Test func releasingItEndsTheObservation() async throws {
        let p = Player(provider: FakeVoiceProvider())
        weak var weakly: NowPlaying?
        do {
            let np = NowPlaying(player: p, center: FakeCenter(), commands: FakeCommands())
            weakly = np
            #expect(weakly != nil)
        }
        try await poll { weakly == nil }
        #expect(weakly == nil)
    }
}
