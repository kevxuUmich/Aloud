import Foundation
import os

/// One sentence's render: the SDK's chunk list, then each chunk's samples, in order.
///
/// The engine is one actor and the SDK runs a whole chunk without suspending, so the
/// order renders are asked for is the order they happen in. Every chunk here is queued
/// behind the one before it, and the plan behind the whole of the render before this
/// one, so two sentences never interleave and the sentence being heard is never put
/// behind the one rendered ahead of it. Everything is rendered without being asked for:
/// `samples(ofChunk:)` only waits.
@MainActor final class SentenceRender {
    let key: KokoroVoiceProvider.CacheKey
    /// Finishes once every chunk has been rendered, failed or been cancelled. The next
    /// render waits on it before it plans.
    private(set) var all: Task<Void, Never>!
    private let engine: any KokoroSynthesizing
    private let planning: Task<[String]?, Never>
    private var renders: [Task<[Float]?, Never>] = []
    /// Set by `cancel`, so a chunk task made after it starts cancelled: the plan can land
    /// after the cancel, and `all` would otherwise queue every chunk of a dead sentence.
    private var cancelled = false
    private static let log = Logger(subsystem: "design.kevxu.aloud", category: "kokoro")

    /// `previous` is the render made before this one, whatever became of it: a cancelled
    /// one finishes at once and holds this up by nothing.
    init(key: KokoroVoiceProvider.CacheKey, engine: any KokoroSynthesizing, after previous: SentenceRender?) {
        self.key = key
        self.engine = engine
        let before = previous?.all
        let (text, voice, speed) = (key.text, key.voice, key.speed)
        planning = Task {
            await before?.value
            guard !Task.isCancelled else { return nil }
            do {
                return try await engine.chunks(of: text, voice: voice, speed: speed)
            } catch KokoroEngineError.cancelled {
                return nil
            } catch {
                Self.log.error(
                    "Kokoro could not plan a sentence: \((error as? KokoroEngineError).map(KokoroVoiceProvider.text) ?? error.localizedDescription, privacy: .public)"
                )
                return nil
            }
        }
        all = Task { [self] in
            guard let chunks = await planning.value else { return }
            render(chunks, upTo: chunks.count - 1)
            for r in renders { _ = await r.value }
        }
    }

    /// The chunk texts, or nil when the plan failed or was cancelled.
    var chunks: [String]? {
        get async { await planning.value }
    }

    /// The samples of chunk `i`, once rendered; nil for a chunk that failed, was cancelled
    /// or does not exist.
    func samples(ofChunk i: Int) async -> [Float]? {
        guard let chunks = await planning.value, i >= 0, i < chunks.count else { return nil }
        render(chunks, upTo: i)
        return await renders[i].value
    }

    /// Queues the renders up to chunk `i`, each behind the one before it. Idempotent: the
    /// first of `all` and `samples(ofChunk:)` to run after the plan lands does the work.
    private func render(_ chunks: [String], upTo i: Int) {
        while renders.count <= i {
            let text = chunks[renders.count]
            let previous = renders.last
            let (voice, speed, engine) = (key.voice, key.speed, engine)
            let task = Task<[Float]?, Never> {
                _ = await previous?.value
                guard !Task.isCancelled else { return nil }
                do {
                    return try await engine.synthesize(text, voice: voice, speed: speed)
                } catch KokoroEngineError.cancelled {
                    return nil
                } catch {
                    Self.log.error(
                        "Kokoro could not speak a chunk: \((error as? KokoroEngineError).map(KokoroVoiceProvider.text) ?? error.localizedDescription, privacy: .public)"
                    )
                    return nil
                }
            }
            if cancelled { task.cancel() }
            renders.append(task)
        }
    }

    func cancel() {
        cancelled = true
        planning.cancel()
        renders.forEach { $0.cancel() }
        all.cancel()
    }
}
