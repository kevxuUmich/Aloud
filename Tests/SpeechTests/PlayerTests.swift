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
    /// A rate change while a sentence is being spoken is heard now, not at the next
    /// sentence: the utterance in the air was queued at the old rate and cannot change,
    /// so the player cuts it and speaks the rest of the sentence, from the word it had
    /// reached, at the new one.
    @Test func rateChangeRestartsTheSentenceFromTheCurrentWordAtTheNewRate() {
        let (p, fake) = make()
        p.play()
        fake.word(NSRange(location: 4, length: 3))
        p.rate = .x2
        #expect(fake.stops == 1)
        #expect(fake.spoken.last?.text == "two three.")
        #expect(fake.spoken.last?.rate == .x2)
        #expect(p.sentenceIndex == 0)
        #expect(p.isPlaying)
        // The words of the rest still land in the source where they are.
        fake.word(NSRange(location: 4, length: 5))
        #expect(String(p.script.source[p.wordRange!]) == "three")
        fake.finishCurrent()
        #expect(p.sentenceIndex == 1)
        #expect(fake.spoken.last?.text == "Four five six.")
    }
    /// Before the first word there is nothing to resume from, so the whole sentence is
    /// spoken again; and a change while paused waits for play, like any other.
    @Test func rateChangeBeforeTheFirstWordSpeaksTheWholeSentence() {
        let (p, fake) = make()
        p.play()
        p.rate = .x2
        #expect(fake.spoken.map(\.text) == ["One two three.", "One two three."])
        p.pause()
        p.rate = .x3
        #expect(fake.spoken.count == 2)
        p.play()
        #expect(fake.spoken.last?.rate == .x3)
    }
    /// The clock within a sentence: elapsed runs from the sentence's start on the
    /// timeline, and never past the sentence's own estimate, however long the
    /// synthesizer takes.
    @Test func elapsedRunsWithinTheSentenceAndStopsAtItsEstimate() {
        let (p, fake) = make()
        p.play()
        let start = p.sentenceAnchor!
        p.tick(now: start + .seconds(0.5))
        #expect(abs(p.elapsed.seconds - 0.5) < 0.001)
        p.tick(now: start + .seconds(60))
        #expect(abs(p.elapsed.seconds - 1.125) < 0.001)
        fake.finishCurrent()
        #expect(abs(p.elapsed.seconds - 1.125) < 0.001)
        p.tick(now: p.sentenceAnchor! + .seconds(0.25))
        #expect(abs(p.elapsed.seconds - 1.375) < 0.001)
    }
    /// Pausing holds the clock where it was; seeking and resuming start it again.
    @Test func pauseHoldsTheClockAndPlayRestartsIt() {
        let (p, _) = make()
        p.play()
        p.tick(now: p.sentenceAnchor! + .seconds(0.5))
        p.pause()
        #expect(abs(p.elapsed.seconds - 0.5) < 0.001)
        p.play()
        #expect(p.elapsed == .zero)
        p.tick(now: p.sentenceAnchor! + .seconds(0.5))
        p.seek(to: 2)
        #expect(abs(p.elapsed.seconds - 2.25) < 0.001)
    }
    /// A rate change keeps the share of the sentence already heard: half a sentence at
    /// 1x is still half a sentence at 2x, which is a quarter of the seconds.
    @Test func rateChangeKeepsTheShareOfTheSentenceHeard() {
        let (p, fake) = make()
        p.play()
        fake.word(NSRange(location: 4, length: 3))
        p.tick(now: p.sentenceAnchor! + .seconds(0.5))
        p.rate = .x2
        #expect(abs(p.elapsed.seconds - 0.25) < 0.001)
        #expect(abs(p.progress - 0.25 / 2.25) < 0.001)
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
    /// An empty file has not been read, so play on one does nothing at all: marking it
    /// finished would put "Finished" under a card nobody has heard a word of.
    @Test func playOnAnEmptyScriptDoesNothing() {
        let fake = FakeVoiceProvider()
        let p = Player(provider: fake)
        var done = false
        p.onFinished = { done = true }
        p.play()
        #expect(!done)
        #expect(!p.finished)
        #expect(!p.isPlaying)
        #expect(fake.spoken.isEmpty)
    }
    @Test func loadWhilePlayingStopsCleanly() {
        let (p, fake) = make()
        p.play()
        let next = "Alpha beta gamma. Delta epsilon zeta."
        p.load(Script(source: next, sentences: SentenceSplitter.split(next)), at: 0)
        #expect(!p.isPlaying)
        #expect(p.wordRange == nil)
        #expect(fake.stops == 1)
        #expect(p.sentenceIndex == 0)
        p.play()
        #expect(fake.spoken.last?.text == "Alpha beta gamma.")
        #expect(p.isPlaying)
    }
    @Test func playWhilePlayingDoesNotSpeakTwice() {
        let (p, fake) = make()
        p.play()
        p.play()
        #expect(fake.spoken.count == 1)
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
    /// A voice can be removed in System Settings between launches. The player says so
    /// once and carries on in the system voice rather than falling silent.
    @Test func missingVoiceFallsBackAndReports() {
        let (p, fake) = make()
        var reported: Voice?
        p.onVoiceUnavailable = { reported = $0 }
        p.voice = Voice(id: "ghost", name: "Ghost", language: "en-US", quality: .standard)
        p.play()
        #expect(reported?.id == "ghost")
        #expect(fake.spoken.last?.voice?.id == "fake")
        #expect(p.voice?.id == "fake")
    }
    /// A preview is a deliberate interruption: it pauses where it is rather than
    /// letting the preview's own finish advance the player past the sentence it cut.
    @Test func previewWhilePlayingPausesAtTheCurrentSentence() {
        let (p, fake) = make()
        p.play()
        fake.finishCurrent()
        #expect(p.sentenceIndex == 1)
        let v = Voice(id: "other", name: "Other", language: "en-US", quality: .standard)
        p.preview(v)
        #expect(!p.isPlaying)
        #expect(fake.stops == 1)
        #expect(fake.previewed == [v])
        #expect(p.sentenceIndex == 1)
        p.play()
        #expect(fake.spoken.last?.text == "Four five six.")
    }
}
