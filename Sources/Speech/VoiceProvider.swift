import Foundation

public protocol VoiceProvider: AnyObject, Sendable {
    var voices: [Voice] { get }
    var defaultVoice: Voice? { get }
    @MainActor func speak(
        _ text: String, voice: Voice?, rate: Rate,
        onWord: @escaping @MainActor (NSRange) -> Void,
        onFinish: @escaping @MainActor () -> Void)
    @MainActor func stop()
}
