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
}

/// The sentence every provider previews. One line, so the whole set can be auditioned
/// quickly, and the app's own first sentence so the voice is heard on real prose.
public enum VoicePreview {
    public static let text = "Nobody really teaches you research."
}
