import Foundation

/// Two engines behind one provider, so the player and the picker keep one. The second
/// engine owns the ids under its prefix; everything else is the first's. The list is
/// the second's voices and then the first's, which lets a picker cut a section off the
/// top; the default voice is the first's, the system's.
@MainActor
public final class CompositeVoiceProvider: VoiceProvider {
    private let primary: any VoiceProvider
    private let secondary: any VoiceProvider
    private let secondaryPrefix: String
    /// The voice the last `speak` or `preview` was routed by. `setVolume` carries no
    /// voice of its own and applies to whatever is being spoken, so this is how it
    /// reaches the same engine that is speaking rather than both of them.
    private var speaking: Voice?

    public nonisolated init(primary: any VoiceProvider, secondary: any VoiceProvider, secondaryPrefix: String)
    {
        self.primary = primary
        self.secondary = secondary
        self.secondaryPrefix = secondaryPrefix
    }

    public nonisolated var voices: [Voice] { secondary.voices + primary.voices }
    public nonisolated var defaultVoice: Voice? { primary.defaultVoice }
    public nonisolated func refreshVoices() {
        primary.refreshVoices()
        secondary.refreshVoices()
    }

    private func provider(for voice: Voice?) -> any VoiceProvider {
        voice?.id.hasPrefix(secondaryPrefix) == true ? secondary : primary
    }

    public func speak(
        _ text: String, voice: Voice?, rate: Rate, pause: Duration, volume: Double,
        onWord: @escaping @MainActor (NSRange) -> Void, onFinish: @escaping @MainActor () -> Void
    ) {
        speaking = voice
        provider(for: voice).speak(
            text, voice: voice, rate: rate, pause: pause, volume: volume, onWord: onWord, onFinish: onFinish)
    }

    public func setVolume(_ volume: Double) -> Bool { provider(for: speaking).setVolume(volume) }

    public func setRate(_ rate: Rate) -> Bool { provider(for: speaking).setRate(rate) }

    public func prepare(_ text: String, voice: Voice?, rate: Rate) {
        provider(for: voice).prepare(text, voice: voice, rate: rate)
    }

    public func preview(_ voice: Voice) {
        speaking = voice
        provider(for: voice).preview(voice)
    }

    /// A preview from one engine may be what interrupts speech from the other, so both
    /// are told. Nothing is being spoken afterwards, so the routing for `setVolume` and
    /// `setRate` goes back to the primary, whose answer is false: those two carry no
    /// voice of their own, and an engine that answered yes to one of them while silent
    /// would have the player believe the reader had heard a change nobody made.
    public func stop() {
        speaking = nil
        primary.stop()
        secondary.stop()
    }
}
