import Foundation
import Testing

@testable import Speech

@Suite @MainActor struct CompositeVoiceProviderTests {
    let apple = Voice(id: "com.apple.voice.samantha", name: "Samantha", language: "en-US", quality: .premium)
    let bella = Voice(id: "kokoro.af_bella", name: "Bella", language: "en-US", quality: .premium)

    func make() -> (CompositeVoiceProvider, FakeVoiceProvider, FakeVoiceProvider) {
        let a = FakeVoiceProvider(voices: [apple])
        let k = FakeVoiceProvider(voices: [bella])
        return (CompositeVoiceProvider(primary: a, secondary: k, secondaryPrefix: "kokoro."), a, k)
    }

    /// The list is one list, the second engine's voices first so a section can be cut
    /// off the top of it; the default voice is the system's.
    @Test func voicesAreConcatenatedSecondaryFirst() {
        let (c, _, _) = make()
        #expect(c.voices.map(\.id) == ["kokoro.af_bella", "com.apple.voice.samantha"])
        #expect(c.defaultVoice?.id == "com.apple.voice.samantha")
    }

    @Test func speakAndPrepareGoToTheProviderThePrefixNames() {
        let (c, a, k) = make()
        c.speak("One.", voice: bella, rate: .x1, pause: .zero, volume: 1, onWord: { _ in }, onFinish: {})
        c.prepare("Two.", voice: bella, rate: .x1)
        #expect(k.spoken.map(\.text) == ["One."])
        #expect(k.prepared.map(\.text) == ["Two."])
        #expect(a.spoken.isEmpty && a.prepared.isEmpty)
        c.speak("Three.", voice: apple, rate: .x1, pause: .zero, volume: 1, onWord: { _ in }, onFinish: {})
        c.prepare("Four.", voice: nil, rate: .x1)
        #expect(a.spoken.map(\.text) == ["Three."])
        #expect(a.prepared.map(\.text) == ["Four."])
        #expect(k.spoken.count == 1)
    }

    /// A finish from the routed provider reaches the caller unchanged.
    @Test func callbacksPassThrough() {
        let (c, _, k) = make()
        var finished = 0
        c.speak(
            "One.", voice: bella, rate: .x1, pause: .zero, volume: 1, onWord: { _ in },
            onFinish: { finished += 1 })
        k.finishCurrent()
        #expect(finished == 1)
    }

    @Test func previewIsRoutedByTheVoice() {
        let (c, a, k) = make()
        c.preview(bella)
        c.preview(apple)
        #expect(k.previewed.map(\.id) == ["kokoro.af_bella"])
        #expect(a.previewed.map(\.id) == ["com.apple.voice.samantha"])
    }

    /// A preview from one engine may be interrupting speech from the other, so a stop
    /// reaches both.
    @Test func stopReachesBoth() {
        let (c, a, k) = make()
        c.stop()
        #expect(a.stops == 1 && k.stops == 1)
    }

    @Test func refreshReachesBothAndAChangeInEitherShows() {
        let (c, a, k) = make()
        c.refreshVoices()
        k.voices = []
        #expect(c.voices.map(\.id) == ["com.apple.voice.samantha"])
        a.voices = []
        #expect(c.voices.isEmpty)
    }
}
