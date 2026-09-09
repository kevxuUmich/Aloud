import AVFoundation
import Foundation

@MainActor
public final class AppleVoiceProvider: NSObject, VoiceProvider, AVSpeechSynthesizerDelegate {
    private let synth = AVSpeechSynthesizer()
    private var onWord: (@MainActor (NSRange) -> Void)?
    private var onFinish: (@MainActor () -> Void)?

    public override init() {
        super.init()
        synth.delegate = self
    }

    public nonisolated var voices: [Voice] {
        AVSpeechSynthesisVoice.speechVoices().map {
            Voice(
                id: $0.identifier, name: $0.name, language: $0.language,
                quality: Quality(apple: $0.quality))
        }
    }

    public nonisolated var defaultVoice: Voice? {
        let all = voices
        let lang = AVSpeechSynthesisVoice.currentLanguageCode()
        let candidates = all.filter { $0.language == lang }
        return candidates.max { $0.quality < $1.quality } ?? all.first
    }

    public func speak(
        _ text: String, voice: Voice?, rate: Rate,
        onWord: @escaping @MainActor (NSRange) -> Void, onFinish: @escaping @MainActor () -> Void
    ) {
        let u = AVSpeechUtterance(string: text)
        u.rate = rate.appleRate
        if let id = voice?.id { u.voice = AVSpeechSynthesisVoice(identifier: id) }
        self.onWord = onWord
        self.onFinish = onFinish
        synth.speak(u)
    }

    /// A preview interrupts whatever is being said and speaks for itself. It leaves
    /// `onWord` and `onFinish` alone: the utterance it cancelled belongs to a `Player`,
    /// which will speak the sentence again when it is next asked to.
    public func preview(_ voice: Voice) {
        synth.stopSpeaking(at: .immediate)
        let u = AVSpeechUtterance(string: VoicePreview.text)
        u.rate = Rate.x1.appleRate
        u.voice = AVSpeechSynthesisVoice(identifier: voice.id)
        synth.speak(u)
    }

    public func stop() {
        onWord = nil
        onFinish = nil
        synth.stopSpeaking(at: .immediate)
    }

    public nonisolated func speechSynthesizer(
        _ s: AVSpeechSynthesizer, willSpeakRangeOfSpeechString r: NSRange, utterance: AVSpeechUtterance
    ) {
        Task { @MainActor in self.onWord?(r) }
    }

    public nonisolated func speechSynthesizer(
        _ s: AVSpeechSynthesizer, didFinish utterance: AVSpeechUtterance
    ) {
        Task { @MainActor in
            let f = self.onFinish
            self.onFinish = nil
            self.onWord = nil
            f?()
        }
    }
}

extension Quality {
    init(apple q: AVSpeechSynthesisVoiceQuality) {
        switch q {
        case .premium: self = .premium
        case .enhanced: self = .enhanced
        default: self = .standard
        }
    }
}
