import Foundation
import Testing

@testable import Kokoro

@Suite @MainActor struct SentenceRenderTests {
    typealias Key = KokoroVoiceProvider.CacheKey

    func key(_ text: String) -> Key { Key(text: text, voice: "af_bella", speed: 1) }

    /// Polls a condition read off the engine, for work that lands on a later turn.
    func eventually(_ condition: () async -> Bool) async -> Bool {
        let deadline = ContinuousClock.now + .seconds(5)
        while await !condition() {
            guard ContinuousClock.now < deadline else { return false }
            try? await Task.sleep(for: .milliseconds(5))
        }
        return true
    }

    /// The chunks are the engine's, rendered in order, and every one is rendered without
    /// being asked for: the whole sentence is what a render ahead is for.
    @Test func rendersEveryChunkInOrder() async throws {
        let engine = FakeEngine()
        let r = SentenceRender(key: key("One, | two, | three."), engine: engine, after: nil)
        #expect(await r.chunks == ["One,", "two,", "three."])
        await r.all.value
        #expect(await engine.calls.map(\.text) == ["One,", "two,", "three."])
        #expect(await r.samples(ofChunk: 1)?.count == 4)
        #expect(await r.samples(ofChunk: 3) == nil)
    }

    /// Asking for a chunk waits for it and for nothing after it.
    @Test func aChunkIsHandedOverAsSoonAsItIsRendered() async throws {
        let engine = FakeEngine()
        await engine.hold("two.")
        let r = SentenceRender(key: key("One, | two."), engine: engine, after: nil)
        #expect(await r.samples(ofChunk: 0)?.count == 4)
        #expect(await eventually { await engine.calls.count == 2 })
        await engine.release()
        #expect(await r.samples(ofChunk: 1)?.count == 4)
    }

    /// The engine is one actor: a render made after another waits for all of that one's
    /// chunks before it plans, so the sentence being heard never queues behind the one
    /// rendered ahead of it.
    @Test func aRenderWaitsForTheWholeOfTheOneBeforeIt() async throws {
        let engine = FakeEngine()
        await engine.hold("two.")
        let first = SentenceRender(key: key("One, | two."), engine: engine, after: nil)
        let second = SentenceRender(key: key("Three."), engine: engine, after: first)
        _ = await first.samples(ofChunk: 0)
        try await Task.sleep(for: .milliseconds(50))
        #expect(await engine.chunkCalls == ["One, | two."])
        await engine.release()
        #expect(await second.samples(ofChunk: 0)?.count == 6)
        #expect(await engine.calls.map(\.text) == ["One,", "two.", "Three."])
    }

    /// A cancelled render answers nil for everything and asks the engine for nothing
    /// more; one chained after it is not held up.
    @Test func cancelStopsTheQueue() async throws {
        let engine = FakeEngine()
        await engine.hold("One,")
        let r = SentenceRender(key: key("One, | two."), engine: engine, after: nil)
        let next = SentenceRender(key: key("Three."), engine: engine, after: r)
        // The first chunk is inside the engine when the cancel lands.
        #expect(await eventually { await engine.calls.count == 1 })
        r.cancel()
        await engine.release()
        #expect(await r.samples(ofChunk: 0) == nil)
        #expect(await r.samples(ofChunk: 1) == nil)
        #expect(await next.samples(ofChunk: 0)?.count == 6)
        #expect(await engine.calls.map(\.text) == ["One,", "Three."])
    }

    /// A plan that fails is a sentence with nothing to say: nil chunks, nil samples.
    @Test func aFailedPlanIsNil() async throws {
        let engine = FakeEngine()
        await engine.setFailSynthesis(.nothingToSay)
        let r = SentenceRender(key: key("***"), engine: engine, after: nil)
        #expect(await r.chunks == nil)
        #expect(await r.samples(ofChunk: 0) == nil)
        #expect(await engine.calls.isEmpty)
    }

    /// One chunk failing is that chunk alone: the ones after it still render.
    @Test func aFailedChunkIsNilAndTheRestRender() async throws {
        let engine = FakeEngine()
        await engine.setFailTexts(["two,"])
        let r = SentenceRender(key: key("One, | two, | three."), engine: engine, after: nil)
        #expect(await r.samples(ofChunk: 1) == nil)
        #expect(await r.samples(ofChunk: 2)?.count == 6)
    }
}
