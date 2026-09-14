import AVFoundation
import Foundation

@MainActor
public final class AppleVoiceProvider: NSObject, VoiceProvider, AVSpeechSynthesizerDelegate {
    private let synth: AVSpeechSynthesizer
    private let sleep: @Sendable (Duration) async throws -> Void
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
    /// The silence to leave once `current`'s words have ended, before its `onFinish`.
    private var pause: Duration = .zero
    /// The wait for that silence. It is held here rather than handed to the synthesizer
    /// as the utterance's `postUtteranceDelay`: an `AVSpeechSynthesizer` stopped while
    /// the next utterance waits out that delay never speaks again, and a pause, a skip
    /// or a document opened between two sentences is exactly such a stop. After one,
    /// nothing more was heard until the app was quit. Internal so the suite can wait
    /// on it.
    private(set) var pauseTask: Task<Void, Never>?

    public override convenience init() {
        self.init(synthesizer: AVSpeechSynthesizer())
    }

    init(
        synthesizer: AVSpeechSynthesizer,
        sleep: @escaping @Sendable (Duration) async throws -> Void = { try await Task.sleep(for: $0) }
    ) {
        synth = synthesizer
        self.sleep = sleep
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
                    id: $0.identifier, name: Voice.bareName($0.name), language: $0.language,
                    quality: Quality(apple: $0.quality))
            }
        }
    }

    public nonisolated func refreshVoices() { cache.invalidate() }

    public nonisolated var defaultVoice: Voice? {
        let all = voices
        let lang = AVSpeechSynthesisVoice.currentLanguageCode()
        let candidates = all.filter { $0.language == lang }
        return candidates.max { $0.quality < $1.quality } ?? all.first
    }

    public func speak(
        _ text: String, voice: Voice?, rate: Rate, pause: Duration, volume: Double,
        onWord: @escaping @MainActor (NSRange) -> Void, onFinish: @escaping @MainActor () -> Void
    ) {
        cancelPause()
        let u = AVSpeechUtterance(string: text)
        u.rate = rate.appleRate
        u.volume = Float(volume)
        if let id = voice?.id { u.voice = AVSpeechSynthesisVoice(identifier: id) }
        self.onWord = onWord
        self.onFinish = onFinish
        self.pause = pause
        current = u
        synth.speak(u)
    }

    /// A preview interrupts whatever is being said, or the silence after it, and
    /// speaks for itself. The callbacks go with what it interrupted: that utterance
    /// belongs to a `Player`, which will speak the sentence again when it is next asked to.
    public func preview(_ voice: Voice) {
        // Dropped before the cancel, not after: the delegate's didCancel arrives on
        // another turn, and a callback still installed when it does belongs to an
        // utterance that is no longer being spoken.
        onWord = nil
        onFinish = nil
        cancelPause()
        pause = .zero
        synth.stopSpeaking(at: .immediate)
        let u = AVSpeechUtterance(string: VoicePreview.text)
        u.rate = Rate.x1.appleRate
        u.voice = AVSpeechSynthesisVoice(identifier: voice.id)
        current = u
        synth.speak(u)
    }

    public func stop() {
        cancelPause()
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
            self.finish(after: self.pause, f)
        }
    }

    /// A finished utterance's `onFinish`, once its pause has passed, or at once with no
    /// pause. A stop, a preview or a new utterance in the meantime cancels it.
    private func finish(after pause: Duration, _ f: (@MainActor () -> Void)?) {
        guard pause > .zero else {
            f?()
            return
        }
        pauseTask = Task { [sleep] in
            try? await sleep(pause)
            guard !Task.isCancelled else { return }
            self.pauseTask = nil
            f?()
        }
    }

    private func cancelPause() {
        pauseTask?.cancel()
        pauseTask = nil
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
