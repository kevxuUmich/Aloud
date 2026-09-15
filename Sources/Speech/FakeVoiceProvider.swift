import Foundation

/// Records what it was asked to speak and lets a test drive the callbacks.
/// Shipped in the module so the app can run silent with `--silent`.
@MainActor
public final class FakeVoiceProvider: VoiceProvider {
    public struct Request: Sendable {
        public let text: String
        public let rate: Rate
        public let voice: Voice?
        public let pause: Duration
        public let volume: Double
    }
    public struct Prepared: Sendable {
        public let text: String
        public let voice: Voice?
        public let rate: Rate
    }
    public private(set) var spoken: [Request] = []
    public private(set) var prepared: [Prepared] = []
    public private(set) var stops = 0
    public private(set) var previewed: [Voice] = []
    /// What `setVolume` was asked for, and whether it claims to have applied it. False
    /// is the system voice's answer; true is an engine that owns its player node.
    public private(set) var volumesSet: [Double] = []
    public var handlesVolume = false
    /// The same, for the speed.
    public private(set) var ratesSet: [Rate] = []
    public var handlesRate = false
    private var onWord: (@MainActor (NSRange) -> Void)?
    private var onFinish: (@MainActor () -> Void)?
    /// The set is a lock-guarded value rather than a main-actor property because the
    /// protocol reads it nonisolated; a test changes it to take a voice away.
    private let installed: Installed

    public nonisolated init(
        voices: [Voice] = [Voice(id: "fake", name: "Fake", language: "en-US", quality: .standard)]
    ) {
        installed = Installed(voices)
    }
    public nonisolated var voices: [Voice] {
        get { installed.get() }
        set { installed.set(newValue) }
    }
    public nonisolated var defaultVoice: Voice? { voices.first }
    /// Nothing is cached, so there is nothing to forget.
    public nonisolated func refreshVoices() {}
    public func speak(
        _ text: String, voice: Voice?, rate: Rate, pause: Duration, volume: Double,
        onWord: @escaping @MainActor (NSRange) -> Void, onFinish: @escaping @MainActor () -> Void
    ) {
        spoken.append(Request(text: text, rate: rate, voice: voice, pause: pause, volume: volume))
        self.onWord = onWord
        self.onFinish = onFinish
    }
    public func prepare(_ text: String, voice: Voice?, rate: Rate) {
        prepared.append(Prepared(text: text, voice: voice, rate: rate))
    }
    public func preview(_ voice: Voice) { previewed.append(voice) }
    public func setVolume(_ volume: Double) -> Bool {
        volumesSet.append(volume)
        return handlesVolume
    }
    public func setRate(_ rate: Rate) -> Bool {
        ratesSet.append(rate)
        return handlesRate
    }
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

private final class Installed: @unchecked Sendable {
    private let lock = NSLock()
    private var voices: [Voice]
    init(_ voices: [Voice]) { self.voices = voices }
    func get() -> [Voice] { lock.withLock { voices } }
    func set(_ new: [Voice]) { lock.withLock { voices = new } }
}
