import Foundation
import Observation
import Prose

@Observable @MainActor
public final class Player {
    public static let skipSeconds: Double = 15

    public private(set) var script: Script = .empty
    public private(set) var sentenceIndex = 0
    public private(set) var wordRange: Range<String.Index>?
    public private(set) var isPlaying = false
    public private(set) var finished = false
    public private(set) var timeline: Timeline

    public var rate: Rate = .x1 { didSet { timeline = Timeline(script: script, rate: rate) } }
    public var voice: Voice?

    public var onSentence: ((Int) -> Void)?
    public var onFinished: (() -> Void)?

    private let provider: any VoiceProvider
    private var generation = 0

    public init(provider: any VoiceProvider) {
        self.provider = provider
        self.voice = provider.defaultVoice
        self.timeline = Timeline(script: .empty, rate: .x1)
    }

    public var elapsed: Duration { timeline.elapsed(at: sentenceIndex) }
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
        timeline = Timeline(script: script, rate: rate)
        sentenceIndex = min(max(index, 0), max(script.sentences.count - 1, 0))
        finished = false
        wordRange = nil
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
        onSentence?(sentenceIndex)
        isPlaying = true
        speakCurrent()
    }

    public func pause() {
        stopSpeaking()
        isPlaying = false
    }

    public func toggle() { isPlaying ? pause() : play() }

    public func seek(to index: Int) {
        let wasPlaying = isPlaying
        stopSpeaking()
        sentenceIndex = min(max(index, 0), max(script.sentences.count - 1, 0))
        finished = false
        wordRange = nil
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

    private func speakCurrent() {
        guard sentenceIndex < script.sentences.count else { return }
        generation += 1
        let gen = generation
        let sentence = script.sentences[sentenceIndex]
        provider.speak(
            sentence.text, voice: voice, rate: rate,
            onWord: { [weak self] ns in
                guard let self, gen == self.generation else { return }
                if let r = Range(ns, in: sentence.text) {
                    let lo = self.script.source.index(
                        sentence.range.lowerBound,
                        offsetBy: sentence.text.distance(from: sentence.text.startIndex, to: r.lowerBound))
                    let hi = self.script.source.index(
                        lo, offsetBy: sentence.text.distance(from: r.lowerBound, to: r.upperBound))
                    self.wordRange = lo..<hi
                }
            },
            onFinish: { [weak self] in
                guard let self, gen == self.generation else { return }
                self.advance()
            })
    }

    private func advance() {
        let next = sentenceIndex + 1
        if next < script.sentences.count {
            sentenceIndex = next
            wordRange = nil
            onSentence?(next)
            speakCurrent()
        } else {
            isPlaying = false
            finished = true
            wordRange = nil
            onFinished?()
        }
    }

    private func stopSpeaking() {
        generation += 1
        provider.stop()
    }
}
