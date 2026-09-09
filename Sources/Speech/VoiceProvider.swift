import Foundation

public protocol VoiceProvider: AnyObject, Sendable {
    var voices: [Voice] { get }
    var defaultVoice: Voice? { get }
    @MainActor func speak(
        _ text: String, voice: Voice?, rate: Rate,
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
