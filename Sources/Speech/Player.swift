import Foundation
import Observation
import Prose

@Observable @MainActor
public final class Player {
    /// Nonisolated because it is a constant, and the media-key bindings read it from
    /// outside the main actor to set the transport's skip interval.
    public nonisolated static let skipSeconds: Double = 10

    public private(set) var script: Script = .empty
    public private(set) var sentenceIndex = 0
    public private(set) var wordRange: Range<String.Index>?
    public private(set) var isPlaying = false
    public private(set) var finished = false
    public private(set) var timeline: Timeline

    /// A change while speaking is heard now. The provider is asked to re-time what it is
    /// already playing, and only when it cannot is the sentence cut and the rest of it,
    /// from the word reached, spoken again at the new speed: an utterance queued with a
    /// system voice cannot be re-timed. The clock keeps the share of the sentence
    /// already heard rather than the seconds either way, since a sentence half spoken at
    /// 1x is still half spoken at 2x.
    public var rate: Rate = .x1 {
        didSet {
            timeline = Timeline(script: script, rate: rate, pauses: pauses)
            sentenceOffset = sentenceOffset * oldValue.factor / rate.factor
            guard isPlaying else { return }
            if provider.setRate(rate) { return }
            stopSpeaking()
            speakCurrent(from: currentWordStart, offset: sentenceOffset)
        }
    }
    /// The level the sentences are spoken at, 0 to 1, apart from the system volume.
    /// A change while speaking is heard now. The provider is asked to re-level what it
    /// is already playing, and only when it cannot is the rest of the sentence spoken
    /// again from the word reached, the way a rate change is: an utterance queued with
    /// a system voice cannot be re-levelled. The clock is untouched either way, since
    /// the timing has not changed.
    ///
    /// Computed over `level` rather than observed on itself: `@Observable` makes a
    /// stored property an accessor pair, and a clamp written back from `didSet` would
    /// re-enter the setter without end.
    public var volume: Double {
        get { level }
        set {
            let clamped = min(max(newValue, 0), Player.fullVolume)
            guard clamped != level else { return }
            level = clamped
            guard isPlaying else { return }
            if provider.setVolume(clamped) { return }
            stopSpeaking()
            speakCurrent(from: currentWordStart, offset: sentenceOffset)
        }
    }
    private var level = Player.fullVolume
    public static let fullVolume = 1.0
    /// The arrow keys' step in the clipboard panel: ten from silent to full.
    public static let volumeStep = 0.1
    /// The silences between sentences. A change is heard from the next sentence: the
    /// one in the air keeps the pause it was queued with, which is a beat at most.
    public var pauses: Pauses = .standard {
        didSet { timeline = Timeline(script: script, rate: rate, pauses: pauses) }
    }
    /// Assignment is where availability is settled, so a sentence never pays for the
    /// check and a voice that has gone is reported once rather than once a sentence.
    public var voice: Voice? { didSet { ensureVoiceIsInstalled() } }

    public var onSentence: ((Int) -> Void)?
    public var onFinished: (() -> Void)?
    /// Fired when the chosen voice is no longer installed. The player has already
    /// fallen back to the system voice by the time this runs.
    public var onVoiceUnavailable: ((Voice) -> Void)?

    /// How far into the current sentence the reading is, by the clock: the transport
    /// reads its elapsed time and progress from this so they move second by second
    /// rather than once a sentence. It runs from `sentenceAnchor` while playing,
    /// clamped to the sentence's estimate so a slow synthesizer never shows the bar
    /// past the sentence it is on, and holds still when paused.
    public private(set) var sentenceOffset: Duration = .zero
    /// The instant the current sentence's clock started, less any offset it resumed
    /// with. Internal for the suite, which drives `tick(now:)` from it.
    private(set) var sentenceAnchor: ContinuousClock.Instant?
    private var ticker: Task<Void, Never>?
    /// How often the clock is read while playing. Four times a second keeps a
    /// once-a-second label from visibly lagging the second it turns.
    static let tickInterval: Duration = .milliseconds(250)

    private let provider: any VoiceProvider
    private var generation = 0

    public init(provider: any VoiceProvider) {
        self.provider = provider
        self.voice = provider.defaultVoice
        self.timeline = Timeline(script: .empty, rate: .x1, pauses: .standard)
    }

    public var elapsed: Duration { timeline.elapsed(at: sentenceIndex) + sentenceOffset }
    public var remaining: Duration { timeline.total - elapsed }
    public var progress: Double {
        timeline.total == .zero ? 0 : Timeline.seconds(elapsed) / Timeline.seconds(timeline.total)
    }

    public func load(_ script: Script, at index: Int) {
        if isPlaying {
            // Stopping the synthesizer without dropping the flag stranded playback:
            // the transport read as playing and nothing was being spoken.
            stopSpeaking()
            isPlaying = false
        } else {
            generation += 1
        }
        self.script = script
        timeline = Timeline(script: script, rate: rate, pauses: pauses)
        sentenceIndex = min(max(index, 0), max(script.sentences.count - 1, 0))
        finished = false
        wordRange = nil
        resetClock()
    }

    public func play() {
        // A second press while speaking would queue a duplicate utterance.
        guard !isPlaying else { return }
        // An empty file is not a file that has been read, so it is not finished.
        guard !script.sentences.isEmpty else { return }
        if finished {
            sentenceIndex = 0
            finished = false
        }
        // The set can change while the app is open, so the voice is checked again here
        // as well as at assignment; between them, `speakCurrent` needs no check at all.
        ensureVoiceIsInstalled()
        onSentence?(sentenceIndex)
        isPlaying = true
        speakCurrent()
    }

    public func pause() {
        stopSpeaking()
        isPlaying = false
        // The offset is left where it is: a paused bar stays put. It restarts from
        // zero on play, with the sentence.
        stopTicking()
    }

    public func toggle() { isPlaying ? pause() : play() }

    /// Auditions a voice. It goes through the player rather than straight to the
    /// provider so the interrupted utterance's callbacks are torn down first;
    /// otherwise the preview's own finish would run `advance()` and skip the sentence
    /// it cut. The sentence stays current, so `play()` speaks it again. Resuming is
    /// the reader's move: a preview is a deliberate interruption.
    public func preview(_ voice: Voice) {
        stopSpeaking()
        isPlaying = false
        provider.preview(voice)
    }

    private func ensureVoiceIsInstalled() {
        guard let v = voice, !provider.voices.contains(where: { $0.id == v.id }) else { return }
        voice = provider.defaultVoice
        onVoiceUnavailable?(v)
    }

    /// Asks again whether the chosen voice is still there. Assignment and `play` ask on
    /// their own; this is for the moment a voice goes away without either, when its
    /// engine fails to load.
    public func revalidateVoice() { ensureVoiceIsInstalled() }

    public func seek(to index: Int) {
        let wasPlaying = isPlaying
        stopSpeaking()
        sentenceIndex = min(max(index, 0), max(script.sentences.count - 1, 0))
        finished = false
        wordRange = nil
        resetClock()
        onSentence?(sentenceIndex)
        if wasPlaying { speakCurrent() }
    }

    public func seek(progress: Double) {
        let target = Timeline.seconds(timeline.total) * min(max(progress, 0), 1)
        seek(to: timeline.index(at: .seconds(target)))
    }

    public func skip(seconds: Double) {
        seek(to: timeline.index(at: elapsed + .seconds(seconds)))
    }

    /// Speaks the current sentence, or the rest of it from `from`. `offset` is where
    /// the sentence's clock resumes: zero for a fresh sentence, and the share already
    /// heard when a rate change re-speaks the rest of one.
    private func speakCurrent(from: String.Index? = nil, offset: Duration = .zero) {
        guard sentenceIndex < script.sentences.count else { return }
        generation += 1
        let gen = generation
        let sentence = script.sentences[sentenceIndex]
        let start = from ?? sentence.text.startIndex
        // The word callbacks' ranges are in the text handed over, which is the whole
        // sentence or its tail, so they are mapped through the tail's own start.
        let spoken = String(sentence.text[start...])
        let base = sentence.text.distance(from: sentence.text.startIndex, to: start)
        sentenceOffset = offset
        sentenceAnchor = .now - offset
        startTicking()
        // The last sentence has none, as in the timeline: nothing follows it to pause before.
        let pause =
            sentenceIndex + 1 < script.sentences.count
            ? (script.endsParagraph(at: sentenceIndex) ? pauses.paragraph : pauses.sentence) : .zero
        provider.speak(
            spoken, voice: voice, rate: rate, pause: pause, volume: volume,
            onWord: { [weak self] ns in
                guard let self, gen == self.generation else { return }
                if let r = Range(ns, in: spoken) {
                    let lo = self.script.source.index(
                        sentence.range.lowerBound,
                        offsetBy: base + spoken.distance(from: spoken.startIndex, to: r.lowerBound))
                    let hi = self.script.source.index(
                        lo, offsetBy: spoken.distance(from: r.lowerBound, to: r.upperBound))
                    self.wordRange = lo..<hi
                }
            },
            onFinish: { [weak self] in
                guard let self, gen == self.generation else { return }
                self.advance()
            })
        // The sentence after this one is handed over now, so an engine that renders
        // ahead has it by the time the boundary comes. The last has nothing after it.
        if sentenceIndex + 1 < script.sentences.count {
            provider.prepare(script.sentences[sentenceIndex + 1].text, voice: voice, rate: rate)
        }
    }

    /// Where the current word starts within the current sentence's text, or nil before
    /// the first word has been reported. `wordRange` is in the source; the sentence's
    /// text is the slice of the source its range names, so the distance carries over.
    private var currentWordStart: String.Index? {
        guard let w = wordRange, sentenceIndex < script.sentences.count else { return nil }
        let sentence = script.sentences[sentenceIndex]
        guard w.lowerBound >= sentence.range.lowerBound, w.lowerBound < sentence.range.upperBound
        else { return nil }
        return sentence.text.index(
            sentence.text.startIndex,
            offsetBy: script.source.distance(from: sentence.range.lowerBound, to: w.lowerBound))
    }

    /// One reading of the clock. Public to the module so the suite can drive it
    /// without waiting; the ticker calls it on the interval while playing.
    func tick(now: ContinuousClock.Instant) {
        guard let anchor = sentenceAnchor else { return }
        sentenceOffset = min(now - anchor, timeline.duration(at: sentenceIndex))
    }

    private func startTicking() {
        ticker?.cancel()
        ticker = Task { [weak self] in
            while !Task.isCancelled {
                try? await Task.sleep(for: Self.tickInterval)
                guard let self, !Task.isCancelled else { return }
                self.tick(now: .now)
            }
        }
    }

    private func stopTicking() {
        ticker?.cancel()
        ticker = nil
        sentenceAnchor = nil
    }

    /// The clock back to the start of a sentence: a load, a seek, or the next sentence.
    private func resetClock() {
        stopTicking()
        sentenceOffset = .zero
    }

    private func advance() {
        let next = sentenceIndex + 1
        if next < script.sentences.count {
            sentenceIndex = next
            wordRange = nil
            resetClock()
            onSentence?(next)
            speakCurrent()
        } else {
            isPlaying = false
            finished = true
            wordRange = nil
            // The bar reads full at the end, not a sentence short of it.
            stopTicking()
            sentenceOffset = timeline.duration(at: sentenceIndex)
            onFinished?()
        }
    }

    private func stopSpeaking() {
        generation += 1
        provider.stop()
    }
}
