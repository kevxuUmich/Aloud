import Foundation
import Prose
import Testing

@testable import Speech

@Suite @MainActor struct PlayerTests {
    func make() -> (Player, FakeVoiceProvider) {
        let fake = FakeVoiceProvider()
        let p = Player(provider: fake)
        let source = "One two three. Four five six. Seven eight nine. Ten eleven twelve."
        p.load(Script(source: source, sentences: SentenceSplitter.split(source)), at: 0)
        return (p, fake)
    }
    @Test func playSpeaksSentenceBySentence() {
        let (p, fake) = make()
        p.play()
        #expect(fake.spoken.map(\.text) == ["One two three."])
        fake.finishCurrent()
        #expect(fake.spoken.map(\.text) == ["One two three.", "Four five six."])
        #expect(p.sentenceIndex == 1)
        #expect(p.isPlaying)
    }
    @Test func finishesAfterTheLastSentence() {
        let (p, fake) = make()
        var done = false
        p.onFinished = { done = true }
        p.seek(to: 3); p.play()
        fake.finishCurrent()
        #expect(done); #expect(!p.isPlaying); #expect(p.finished)
    }
    @Test func rateChangeAppliesAtTheNextSentence() {
        let (p, fake) = make()
        p.play()
        p.rate = .x2
        #expect(fake.spoken.last?.rate == .x1)
        fake.finishCurrent()
        #expect(fake.spoken.last?.rate == .x2)
    }
    @Test func seekWhilePlayingRestartsAtTheTarget() {
        let (p, fake) = make()
        p.play(); p.seek(to: 2)
        #expect(fake.stops == 1)
        #expect(fake.spoken.last?.text == "Seven eight nine.")
        #expect(p.isPlaying)
    }
    @Test func skipLandsOnASentenceBoundary() {
        let (p, _) = make()
        // each 3-word sentence is 1.125 s at 1x; 15 s forward from 0 clamps to the last sentence
        p.skip(seconds: 15)
        #expect(p.sentenceIndex == 3)
        p.skip(seconds: -15)
        #expect(p.sentenceIndex == 0)
    }
    @Test func wordRangeMapsIntoTheSource() {
        let (p, fake) = make()
        p.play()
        fake.word(NSRange(location: 4, length: 3))
        #expect(String(p.script.source[p.wordRange!]) == "two")
    }
    @Test func pauseStopsAndKeepsIndex() {
        let (p, fake) = make()
        p.play(); fake.finishCurrent(); p.pause()
        #expect(!p.isPlaying); #expect(p.sentenceIndex == 1); #expect(fake.stops == 1)
    }
    @Test func progressIsATimelineFraction() {
        let (p, _) = make()
        p.seek(to: 2)
        #expect(abs(p.progress - 0.5) < 0.001)
        p.seek(progress: 0.9)
        #expect(p.sentenceIndex == 3)
    }
    @Test func playOnEmptyScriptFinishesImmediately() {
        let fake = FakeVoiceProvider()
        let p = Player(provider: fake)
        var done = false
        p.onFinished = { done = true }
        p.play()
        #expect(done)
        #expect(p.finished)
        #expect(!p.isPlaying)
        #expect(fake.spoken.isEmpty)
    }
    @Test func playReportsTheStartingSentence() {
        let (p, _) = make()
        let source = "One two three. Four five six. Seven eight nine. Ten eleven twelve."
        p.load(Script(source: source, sentences: SentenceSplitter.split(source)), at: 2)
        var reported: [Int] = []
        p.onSentence = { reported.append($0) }
        p.play()
        #expect(reported == [2])
    }
    @Test func resumeAfterPauseReportsTheSentenceAgain() {
        let (p, fake) = make()
        var reported: [Int] = []
        p.onSentence = { reported.append($0) }
        p.play()
        fake.finishCurrent()
        p.pause()
        p.play()
        #expect(reported == [0, 1, 1])
    }
}
