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
        var play: (() -> Void)?
        var pause: (() -> Void)?
        var toggle: (() -> Void)?
        var forward: (() -> Void)?
        var backward: (() -> Void)?
        func bind(
            play: @escaping () -> Void, pause: @escaping () -> Void, toggle: @escaping () -> Void,
            skipForward: @escaping () -> Void, skipBackward: @escaping () -> Void
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
        np.update(title: "Essay")
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
    /// The observation is what makes the panel keep up with the player without anyone
    /// calling `update`. Loading a longer script changes the timeline, and the pushed
    /// duration has to follow it.
    @Test func aLoadPushesTheNewDuration() async throws {
        let fake = FakeVoiceProvider()
        let p = Player(provider: fake)
        let center = FakeCenter()
        let np = NowPlaying(player: p, center: center, commands: FakeCommands())
        np.update(title: "Essay")
        let src = "One two three. Four five six. Seven eight nine."
        p.load(Script(source: src, sentences: SentenceSplitter.split(src)), at: 0)
        try await Task.sleep(for: .milliseconds(50))
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
        try await Task.sleep(for: .milliseconds(50))
        #expect(weakly == nil)
    }
}
