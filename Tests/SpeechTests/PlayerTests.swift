import Foundation
import Prose
import Testing

@testable import Speech

@Suite @MainActor struct PlayerTests {
    /// The fixture speaks with no pauses, so a sentence's slot is its words alone and
    /// the clock arithmetic below reads straight off the word count. The pause test
    /// builds its own.
    func make() -> (Player, FakeVoiceProvider) {
        let fake = FakeVoiceProvider()
        let p = Player(provider: fake)
        p.pauses = .none
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
    /// The level reaches the provider with every sentence, full by default.
    @Test func volumeReachesTheProvider() {
        let (p, fake) = make()
        p.play()
        #expect(fake.spoken.last?.volume == 1)
        fake.finishCurrent()
        p.volume = 0.4
        fake.finishCurrent()
        #expect(fake.spoken.last?.volume == 0.4)
    }
    /// A level change while a sentence is being spoken is heard now, the way a rate
    /// change is: the rest of the sentence is spoken again from the word reached.
    @Test func volumeChangeRestartsTheSentenceFromTheCurrentWord() {
        let (p, fake) = make()
        p.play()
        fake.word(NSRange(location: 4, length: 3))
        p.volume = 0.5
        #expect(fake.stops == 1)
        #expect(fake.spoken.last?.text == "two three.")
        #expect(fake.spoken.last?.volume == 0.5)
        #expect(p.isPlaying)
        p.pause()
        p.volume = 0.2
        #expect(fake.spoken.count == 2)
    }
    /// A provider that can re-level what it is already playing is asked first, and when
    /// it says it has, nothing is spoken again: on the Kokoro engine a re-speak is a
    /// whole re-synthesis, and volume is the one parameter that needs no new audio.
    @Test func aProviderThatRelevelsIsNotAskedToSpeakAgain() {
        let (p, fake) = make()
        fake.handlesVolume = true
        p.play()
        fake.word(NSRange(location: 4, length: 3))
        p.volume = 0.5
        #expect(fake.volumesSet == [0.5])
        #expect(fake.stops == 0)
        #expect(fake.spoken.count == 1)
        #expect(p.volume == 0.5)
        // A provider that cannot keeps today's behaviour.
        fake.handlesVolume = false
        p.volume = 0.2
        #expect(fake.stops == 1)
        #expect(fake.spoken.count == 2)
        #expect(fake.spoken.last?.volume == 0.2)
    }
    /// A provider that can re-time what it is already playing is asked first, and when it
    /// says it has, the sentence is not spoken again. For an engine that renders ahead,
    /// a re-speak would throw away the rendering it has already made of the next sentence
    /// as well as the one being heard.
    @Test func aProviderThatRetimesIsNotAskedToSpeakAgain() {
        let (p, fake) = make()
        fake.handlesRate = true
        p.play()
        fake.word(NSRange(location: 4, length: 3))
        p.rate = .x2
        #expect(fake.ratesSet == [.x2])
        #expect(fake.stops == 0)
        #expect(fake.spoken.count == 1)
        #expect(p.rate == .x2)
        // The clock still moves with the rate: the audio really did get faster.
        #expect(p.timeline.total == Timeline(script: p.script, rate: .x2, pauses: p.pauses).total)
        // A provider that cannot keeps today's behaviour.
        fake.handlesRate = false
        p.rate = .x3
        #expect(fake.stops == 1)
        #expect(fake.spoken.count == 2)
        #expect(fake.spoken.last?.rate == .x3)
    }
    /// The level is clamped to what the synthesizer accepts.
    @Test func volumeIsClampedToTheUnitRange() {
        let (p, _) = make()
        p.volume = 3
        #expect(p.volume == 1)
        p.volume = -1
        #expect(p.volume == 0)
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
    /// Each utterance carries the silence to leave after it: the sentence pause, or
    /// the paragraph pause where the sentence ends a paragraph. A change reaches the
    /// next sentence without restarting the one in the air.
    @Test func eachSentenceCarriesItsPause() {
        let fake = FakeVoiceProvider()
        let p = Player(provider: fake)
        let source = "One two three.\n\nFour five six. Seven eight nine. Ten eleven twelve."
        p.load(Script(source: source, sentences: SentenceSplitter.split(source)), at: 0)
        p.play()
        #expect(fake.spoken.last?.pause == Pauses.standard.paragraph)
        fake.finishCurrent()
        #expect(fake.spoken.last?.pause == Pauses.standard.sentence)
        p.pauses = Pauses(sentence: .seconds(1), paragraph: .seconds(2))
        #expect(fake.spoken.count == 2)
        #expect(p.timeline.duration(at: 1) == .seconds(1.125) + .seconds(1))
        fake.finishCurrent()
        #expect(fake.spoken.last?.pause == .seconds(1))
    }
    /// The last sentence has no pause, as it has none in the timeline: nothing follows
    /// it, and a silence held after it would only hold back the end of the document.
    @Test func theLastSentenceCarriesNoPause() {
        let fake = FakeVoiceProvider()
        let p = Player(provider: fake)
        let source = "One two three.\n\nFour five six."
        p.load(Script(source: source, sentences: SentenceSplitter.split(source)), at: 0)
        p.play()
        #expect(fake.spoken.last?.pause == Pauses.standard.paragraph)
        fake.finishCurrent()
        #expect(fake.spoken.last?.text == "Four five six.")
        #expect(fake.spoken.last?.pause == .zero)
    }
    @Test func seekWhilePlayingRestartsAtTheTarget() {
        let (p, fake) = make()
        p.play(); p.seek(to: 2)
        #expect(fake.stops == 1)
        #expect(fake.spoken.last?.text == "Seven eight nine.")
        #expect(p.isPlaying)
    }
    @Test func theTransportSkipsTenSeconds() { #expect(Player.skipSeconds == 10) }
    /// The arrow keys' step: ten of them from silent to full, clamped by the setter.
    @Test func theVolumeStepIsATenth() {
        let (p, _) = make()
        p.volume = Player.fullVolume
        p.volume += Player.volumeStep
        #expect(p.volume == Player.fullVolume)
        p.volume -= Player.volumeStep
        #expect(abs(p.volume - 0.9) < 0.0001)
    }
    @Test func skipLandsOnASentenceBoundary() {
        let (p, _) = make()
        // each 3-word sentence is 1.125 s at 1x, plus its pause; 10 s forward from 0
        // clamps to the last sentence
        p.skip(seconds: 10)
        #expect(p.sentenceIndex == 3)
        p.skip(seconds: -10)
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

    /// While one sentence is spoken the next is handed to the provider to get ready, so
    /// an engine that synthesizes ahead can leave no gap at the boundary. The last
    /// sentence has nothing after it, and nothing is prepared.
    @Test func theNextSentenceIsPreparedWhileTheCurrentOneIsSpoken() {
        let (p, fake) = make()
        p.rate = .x15
        p.play()
        #expect(fake.prepared.map(\.text) == ["Four five six."])
        #expect(fake.prepared.last?.rate == .x15)
        fake.finishCurrent()
        #expect(fake.prepared.map(\.text) == ["Four five six.", "Seven eight nine."])
        fake.finishCurrent()
        fake.finishCurrent()
        #expect(p.sentenceIndex == 3)
        #expect(fake.prepared.map(\.text) == ["Four five six.", "Seven eight nine.", "Ten eleven twelve."])
    }

    /// A voice can stop being available without being reassigned, when its engine
    /// fails to load. The player is told to look again and falls back as it does for a
    /// voice removed in System Settings.
    @Test func revalidateFallsBackWhenTheVoiceHasGone() {
        let fake = FakeVoiceProvider(voices: [
            Voice(id: "fake", name: "Fake", language: "en-US", quality: .standard),
            Voice(id: "kokoro.af_bella", name: "Bella", language: "en-US", quality: .premium),
        ])
        let p = Player(provider: fake)
        p.voice = fake.voices[1]
        var unavailable: [Voice] = []
        p.onVoiceUnavailable = { unavailable.append($0) }
        fake.voices = [fake.voices[0]]
        p.revalidateVoice()
        #expect(p.voice?.id == "fake")
        #expect(unavailable.map(\.id) == ["kokoro.af_bella"])
    }
}
