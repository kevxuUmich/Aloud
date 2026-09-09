import AVFoundation
import Foundation

@MainActor
public final class AppleVoiceProvider: NSObject, VoiceProvider, AVSpeechSynthesizerDelegate {
    private let synth = AVSpeechSynthesizer()
    /// `voices` is read on every popover render and was read on every sentence, and
    /// `speechVoices()` is not cheap. The cache is nonisolated because the protocol
    /// requirement is, so it carries its own lock.
    private let cache = VoiceCache()
    private var onWord: (@MainActor (NSRange) -> Void)?
    private var onFinish: (@MainActor () -> Void)?
    /// The utterance the callbacks above belong to. A cancel arrives on a later turn
    /// than the `stopSpeaking` that caused it, by which time a new `speak` may have
    /// installed its own callbacks; clearing on a stale one wiped them and playback
    /// stalled with nothing to report it. Identity is the whole guard, and the
    /// reference is held rather than just its `ObjectIdentifier` so a freed
    /// utterance's address cannot be reused under the comparison.
    private var current: AVSpeechUtterance?

    public override init() {
        super.init()
        synth.delegate = self
        // Installing or removing a voice in System Settings is the one thing that can
        // change the set while the app is open.
        NotificationCenter.default.addObserver(
            forName: AVSpeechSynthesizer.availableVoicesDidChangeNotification, object: nil,
            queue: nil
        ) { [cache] _ in cache.invalidate() }
    }

    public nonisolated var voices: [Voice] {
        cache.voices {
            AVSpeechSynthesisVoice.speechVoices().map {
                Voice(
                    id: $0.identifier, name: $0.name, language: $0.language,
                    quality: Quality(apple: $0.quality))
            }
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
        current = u
        synth.speak(u)
    }

    /// A preview interrupts whatever is being said and speaks for itself. It leaves
    /// `onWord` and `onFinish` alone: the utterance it cancelled belongs to a `Player`,
    /// which will speak the sentence again when it is next asked to.
    public func preview(_ voice: Voice) {
        // Dropped before the cancel, not after: the delegate's didCancel arrives on
        // another turn, and a callback still installed when it does belongs to an
        // utterance that is no longer being spoken.
        onWord = nil
        onFinish = nil
        synth.stopSpeaking(at: .immediate)
        let u = AVSpeechUtterance(string: VoicePreview.text)
        u.rate = Rate.x1.appleRate
        u.voice = AVSpeechSynthesisVoice(identifier: voice.id)
        current = u
        synth.speak(u)
    }

    public func stop() {
        onWord = nil
        onFinish = nil
        current = nil
        synth.stopSpeaking(at: .immediate)
    }

    public nonisolated func speechSynthesizer(
        _ s: AVSpeechSynthesizer, willSpeakRangeOfSpeechString r: NSRange, utterance: AVSpeechUtterance
    ) {
        Task { @MainActor in self.onWord?(r) }
    }

    public nonisolated func speechSynthesizer(
        _ s: AVSpeechSynthesizer, didCancel utterance: AVSpeechUtterance
    ) {
        let id = ObjectIdentifier(utterance)
        Task { @MainActor in
            guard id == self.current.map(ObjectIdentifier.init) else { return }
            self.current = nil
            self.onFinish = nil
            self.onWord = nil
        }
    }

    public nonisolated func speechSynthesizer(
        _ s: AVSpeechSynthesizer, didFinish utterance: AVSpeechUtterance
    ) {
        let id = ObjectIdentifier(utterance)
        Task { @MainActor in
            guard id == self.current.map(ObjectIdentifier.init) else { return }
            self.current = nil
            let f = self.onFinish
            self.onFinish = nil
            self.onWord = nil
            f?()
        }
    }
}

/// The installed set behind a lock, so `voices` can stay nonisolated.
private final class VoiceCache: @unchecked Sendable {
    private let lock = NSLock()
    private var cached: [Voice]?
    func voices(_ read: () -> [Voice]) -> [Voice] {
        lock.lock()
        if let cached {
            lock.unlock()
            return cached
        }
        lock.unlock()
        let fresh = read()
        lock.lock()
        cached = fresh
        lock.unlock()
        return fresh
    }
    func invalidate() {
        lock.lock()
        cached = nil
        lock.unlock()
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
