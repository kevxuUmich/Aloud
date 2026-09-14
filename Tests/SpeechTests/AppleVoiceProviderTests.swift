import AVFoundation
import Foundation
import Testing

@testable import Speech

@Suite @MainActor struct AppleVoiceProviderTests {
    /// Keeps what it is asked to speak and says nothing, so a test can finish an
    /// utterance itself by calling the delegate.
    final class SilentSynthesizer: AVSpeechSynthesizer {
        var spoken: [AVSpeechUtterance] = []
        var stops = 0
        override func speak(_ utterance: AVSpeechUtterance) { spoken.append(utterance) }
        override func stopSpeaking(at boundary: AVSpeechBoundary) -> Bool {
            stops += 1
            return true
        }
    }

    /// A sleep that lasts until the test lets it go, and remembers how long it was
    /// asked to be. Cancellation is seen when it is let go, as a real sleep's would be
    /// at once.
    @MainActor final class HeldSleep {
        var asked: [Duration] = []
        private var waiting: [CheckedContinuation<Void, Never>] = []
        func sleep(_ d: Duration) async throws {
            asked.append(d)
            await withCheckedContinuation { waiting.append($0) }
            try Task.checkCancellation()
        }
        func release() {
            let w = waiting
            waiting = []
            w.forEach { $0.resume() }
        }
    }

    func make() -> (AppleVoiceProvider, SilentSynthesizer, HeldSleep) {
        let synth = SilentSynthesizer()
        let held = HeldSleep()
        let provider = AppleVoiceProvider(synthesizer: synth, sleep: { try await held.sleep($0) })
        return (provider, synth, held)
    }

    /// Polls until `condition` holds, for the callbacks that arrive on a later turn.
    /// False when the time runs out.
    func until(_ timeout: Duration, _ condition: () -> Bool) async -> Bool {
        let deadline = ContinuousClock.now + timeout
        while !condition() {
            guard ContinuousClock.now < deadline else { return false }
            try? await Task.sleep(for: .milliseconds(5))
        }
        return true
    }

    /// The system synthesizer, silent. A stop that lands just after the player has
    /// moved on to the next sentence is a pause, a skip, or a new document opened at
    /// the wrong moment, and the synthesizer must still speak what comes after it.
    /// It went silent for good when the next sentence was waiting out the one
    /// before's `postUtteranceDelay`: nothing more was spoken until the app quit.
    @Test func aStopJustAfterTheNextSentenceIsQueuedLeavesTheSynthesizerSpeaking() async {
        let provider = AppleVoiceProvider()
        var finished: [String] = []
        func say(_ text: String) {
            provider.speak(
                text, voice: nil, rate: .x2, pause: .milliseconds(200), volume: 0, onWord: { _ in },
                onFinish: { finished.append(text) })
        }
        say("One.")
        #expect(await until(.seconds(10)) { finished == ["One."] })
        // What the player does when a sentence finishes: the next one, straight away.
        say("Two, three, four, five, six, seven.")
        try? await Task.sleep(for: .milliseconds(100))
        provider.stop()
        say("Eight.")
        #expect(await until(.seconds(10)) { finished.last == "Eight." })
    }

    /// The silence after a sentence is held here, after its words have ended, and the
    /// sentence reports finished once it has passed. The synthesizer is never handed
    /// the silence as a delay of its own.
    @Test func theSentenceReportsFinishedOnceItsPauseHasPassed() async throws {
        let (provider, synth, held) = make()
        var finished = 0
        provider.speak(
            "One two three.", voice: nil, rate: .x1, pause: .milliseconds(300), volume: 1,
            onWord: { _ in }, onFinish: { finished += 1 })
        let u = try #require(synth.spoken.last)
        #expect(u.postUtteranceDelay == 0)
        provider.speechSynthesizer(synth, didFinish: u)
        #expect(await until(.seconds(5)) { held.asked == [.milliseconds(300)] })
        #expect(finished == 0)
        let pause = try #require(provider.pauseTask)
        held.release()
        await pause.value
        #expect(finished == 1)
    }

    /// A stop in the silence after a sentence is a stop: the sentence never reports
    /// finished, so the player is not moved on to the next one behind the reader's back.
    @Test func aStopDuringThePauseMeansTheSentenceNeverReportsFinished() async throws {
        let (provider, synth, held) = make()
        var finished = 0
        provider.speak(
            "One two three.", voice: nil, rate: .x1, pause: .milliseconds(300), volume: 1,
            onWord: { _ in }, onFinish: { finished += 1 })
        provider.speechSynthesizer(synth, didFinish: try #require(synth.spoken.last))
        #expect(await until(.seconds(5)) { held.asked.count == 1 })
        let pause = try #require(provider.pauseTask)
        provider.stop()
        held.release()
        await pause.value
        #expect(finished == 0)
    }

    /// A preview interrupts the silence as it interrupts the words.
    @Test func aPreviewDuringThePauseMeansTheSentenceNeverReportsFinished() async throws {
        let (provider, synth, held) = make()
        var finished = 0
        provider.speak(
            "One two three.", voice: nil, rate: .x1, pause: .milliseconds(300), volume: 1,
            onWord: { _ in }, onFinish: { finished += 1 })
        provider.speechSynthesizer(synth, didFinish: try #require(synth.spoken.last))
        #expect(await until(.seconds(5)) { held.asked.count == 1 })
        let pause = try #require(provider.pauseTask)
        provider.preview(Voice(id: "any", name: "Any", language: "en-US", quality: .standard))
        held.release()
        await pause.value
        #expect(finished == 0)
    }

    /// A new sentence spoken in the silence takes over from the one before it, whose
    /// finish then never comes: it would move the player on past the new one.
    @Test func aNewSentenceDuringThePauseMeansTheOneBeforeNeverReportsFinished() async throws {
        let (provider, synth, held) = make()
        var finished: [String] = []
        provider.speak(
            "One two three.", voice: nil, rate: .x1, pause: .milliseconds(300), volume: 1,
            onWord: { _ in }, onFinish: { finished.append("one") })
        provider.speechSynthesizer(synth, didFinish: try #require(synth.spoken.last))
        #expect(await until(.seconds(5)) { held.asked.count == 1 })
        let pause = try #require(provider.pauseTask)
        provider.speak(
            "Four five six.", voice: nil, rate: .x1, pause: .zero, volume: 1,
            onWord: { _ in }, onFinish: { finished.append("four") })
        held.release()
        await pause.value
        #expect(finished.isEmpty)
        provider.speechSynthesizer(synth, didFinish: try #require(synth.spoken.last))
        #expect(await until(.seconds(5)) { finished == ["four"] })
    }

    /// With no pause there is nothing to wait for: the sentence reports finished on
    /// the turn its words end.
    @Test func aSentenceWithNoPauseReportsFinishedAtOnce() async throws {
        let (provider, synth, held) = make()
        var finished = 0
        provider.speak(
            "One two three.", voice: nil, rate: .x1, pause: .zero, volume: 1,
            onWord: { _ in }, onFinish: { finished += 1 })
        provider.speechSynthesizer(synth, didFinish: try #require(synth.spoken.last))
        #expect(await until(.seconds(5)) { finished == 1 })
        #expect(held.asked.isEmpty)
    }
}
