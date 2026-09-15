import Foundation
import Testing

@testable import Kokoro

/// The prewarm sequence behind `load`: the buckets a first sentence does not need, warmed
/// in the order a reader meets them. The SDK is not here, so the prewarm itself is the
/// one the engine was handed; what is under test is the order, the cancellation and the
/// handle, which is where the bugs were.
@Suite struct KokoroEnginePrewarmTests {
    /// Records each bucket it was asked for, and holds the caller when told to, so a test
    /// can unload in the middle of the sequence.
    actor WarmLog {
        private(set) var calls: [(text: String, speed: Float)] = []
        private var waiters: [CheckedContinuation<Void, Never>] = []
        private var holding = false
        var texts: [String] { calls.map(\.text) }
        var speeds: [Float] { calls.map(\.speed) }
        func hold() { holding = true }
        func record(_ text: String, _ speed: Float) async {
            calls.append((text, speed))
            if holding { await withCheckedContinuation { waiters.append($0) } }
        }
        func release() {
            holding = false
            let waiting = waiters
            waiters = []
            waiting.forEach { $0.resume() }
        }
    }

    func make(_ log: WarmLog) -> KokoroEngine {
        KokoroEngine(prewarm: { text, speed in await log.record(text, speed) })
    }

    /// Waits for a condition read off an actor, so a test never hangs on one that never
    /// comes true.
    func eventually(_ condition: () async -> Bool) async -> Bool {
        let deadline = ContinuousClock.now + .seconds(5)
        while await !condition() {
            guard ContinuousClock.now < deadline else { return false }
            try? await Task.sleep(for: .milliseconds(5))
        }
        return true
    }

    @Test func theBucketsBehindTheFirstWarmInOrder() async throws {
        let log = WarmLog()
        let engine = make(log)
        await engine.warmRemainingBuckets()
        let task = await engine.warmTask
        await task?.value
        #expect(await log.texts == KokoroEngine.prewarms.dropFirst().map(\.text))
        #expect(await log.speeds == KokoroEngine.prewarms.dropFirst().map(\.speed))
    }

    /// An unload stops the sequence where it is rather than letting it warm buckets for a
    /// model that is being given back.
    @Test func unloadStopsTheSequence() async throws {
        let log = WarmLog()
        await log.hold()
        let engine = make(log)
        await engine.warmRemainingBuckets()
        let task = await engine.warmTask
        #expect(await eventually { await log.calls.count == 1 })
        await engine.unload()
        await log.release()
        await task?.value
        #expect(await log.calls.count == 1)
        #expect(await engine.warmTask == nil)
    }

    /// A load, an unload and a second load: the first sequence finishing must not clear
    /// the handle the second one stored, or a later unload has nothing left to cancel.
    @Test func aSecondSequenceKeepsItsOwnHandle() async throws {
        let log = WarmLog()
        await log.hold()
        let engine = make(log)
        await engine.warmRemainingBuckets()
        let first = await engine.warmTask
        #expect(await eventually { await log.calls.count == 1 })
        await engine.warmRemainingBuckets()
        let second = await engine.warmTask
        #expect(second != first)
        await log.release()
        await first?.value
        await second?.value
        #expect(await engine.warmTask == second)
    }
}
