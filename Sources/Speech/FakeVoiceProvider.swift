import Foundation

/// Records what it was asked to speak and lets a test drive the callbacks.
/// Shipped in the module so the app can run silent with `--silent`.
@MainActor
public final class FakeVoiceProvider: VoiceProvider {
    public struct Request: Sendable {
        public let text: String
        public let rate: Rate
        public let voice: Voice?
    }
    public private(set) var spoken: [Request] = []
    public private(set) var stops = 0
    public private(set) var previewed: [Voice] = []
    private var onWord: (@MainActor (NSRange) -> Void)?
    private var onFinish: (@MainActor () -> Void)?

    public nonisolated init() {}

    public nonisolated var voices: [Voice] {
        [Voice(id: "fake", name: "Fake", language: "en-US", quality: .standard)]
    }
    public nonisolated var defaultVoice: Voice? { voices.first }
    /// Nothing is cached, so there is nothing to forget.
    public nonisolated func refreshVoices() {}

    public func speak(
        _ text: String, voice: Voice?, rate: Rate,
        onWord: @escaping @MainActor (NSRange) -> Void, onFinish: @escaping @MainActor () -> Void
    ) {
        spoken.append(Request(text: text, rate: rate, voice: voice))
        self.onWord = onWord
        self.onFinish = onFinish
    }

    public func preview(_ voice: Voice) { previewed.append(voice) }

    public func stop() {
        stops += 1
        onWord = nil
        onFinish = nil
    }

    public func finishCurrent() {
        let f = onFinish
        onFinish = nil
        onWord = nil
        f?()
    }
    public func word(_ range: NSRange) { onWord?(range) }
}
