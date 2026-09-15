import Foundation

public protocol VoiceProvider: AnyObject, Sendable {
    var voices: [Voice] { get }
    var defaultVoice: Voice? { get }
    /// Forgets whatever the provider has cached about the installed set, so the next
    /// read of `voices` asks the system again. A voice downloaded while the app was
    /// running is otherwise invisible until the app is restarted.
    func refreshVoices()
    /// `pause` is the silence to leave after the text, before whatever is spoken next.
    /// `volume` is the utterance's own level, 0 to 1, apart from the system's.
    @MainActor func speak(
        _ text: String, voice: Voice?, rate: Rate, pause: Duration, volume: Double,
        onWord: @escaping @MainActor (NSRange) -> Void,
        onFinish: @escaping @MainActor () -> Void)
    @MainActor func stop()
    /// Speaks one fixed sentence in the given voice, so a reader can hear a voice
    /// before picking it. It does not touch the callbacks a `Player` has installed.
    @MainActor func preview(_ voice: Voice)
    /// Tells the provider what will be asked for next, so an engine that synthesizes
    /// ahead can have it ready. Nothing is heard; a `speak` for the same text, voice
    /// and rate may then start without a gap. The system voice needs no warning and
    /// takes the default, which does nothing.
    @MainActor func prepare(_ text: String, voice: Voice?, rate: Rate)
    /// Applies a new level to whatever is being spoken now. True when the provider did,
    /// so the caller has nothing more to do; false when it cannot, and the caller has to
    /// speak the sentence again to be heard. An engine that queues an utterance cannot
    /// re-level it; one that owns a player node can, and for it a re-speak would mean a
    /// whole re-synthesis for a parameter that needs no new audio.
    @MainActor func setVolume(_ volume: Double) -> Bool
    /// Applies a new speed to whatever is being spoken now, the same bargain as
    /// `setVolume`. True when the provider did; false when the sentence has to be spoken
    /// again to be heard at the new speed. Most speeds need new audio and most engines
    /// answer false; one that renders ahead and owns a time stretch can answer true for
    /// the speeds its renderings already cover, and then the sentence it has rendered
    /// ahead survives the change instead of being thrown away with the one being heard.
    @MainActor func setRate(_ rate: Rate) -> Bool
}

extension VoiceProvider {
    @MainActor public func prepare(_ text: String, voice: Voice?, rate: Rate) {}
    @MainActor public func setVolume(_ volume: Double) -> Bool { false }
    @MainActor public func setRate(_ rate: Rate) -> Bool { false }
}

/// The sentence every provider previews. One line, so the whole set can be auditioned
/// quickly, and the app's own first sentence so the voice is heard on real prose.
public enum VoicePreview {
    public static let text = "Nobody really teaches you research."
}
