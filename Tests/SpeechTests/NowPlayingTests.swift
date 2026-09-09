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
}
