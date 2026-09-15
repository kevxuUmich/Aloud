import Foundation
import Speech

@testable import Kokoro

/// The three fakes `KokoroTests` drives the store and the provider with, copied here
/// because test targets do not share sources. Kept the same as the originals in
/// `Tests/KokoroTests`, so a change there is a change to make here too.

/// A downloader a test drives by hand: it records what it was asked and delivers
/// progress, a finished file or a failure when told to.
@MainActor final class FakeDownloader: KokoroDownloading {
    struct Request { let url: URL; let destination: URL; let resumeData: Data? }
    var requests: [Request] = []
    var cancels = 0
    var running = false
    weak var delegate: (any KokoroDownloadDelegate)?
    var destination: URL?
    /// A finished download the real session replays the moment it is created, which is
    /// inside `reattach` and before it returns.
    var replayFinish: Data?

    nonisolated init() {}
    func download(_ url: URL, to destination: URL, resumeData: Data?, delegate: any KokoroDownloadDelegate) {
        requests.append(Request(url: url, destination: destination, resumeData: resumeData))
        self.delegate = delegate
        self.destination = destination
    }
    func reattach(to destination: URL, delegate: any KokoroDownloadDelegate) async -> Bool {
        // Recorded before anything is replayed, as the real downloader records them
        // before it creates the session that does the replaying.
        self.delegate = delegate
        self.destination = destination
        if let replayFinish {
            self.replayFinish = nil
            try? replayFinish.write(to: destination)
            delegate.downloadFinished()
            return false
        }
        return running
    }
    func cancel() { cancels += 1 }

    func progress(_ f: Double) { delegate?.downloadProgressed(f) }
    func finish(with data: Data) throws {
        try data.write(to: destination!)
        delegate?.downloadFinished()
    }
    func fail(_ failure: KokoroDownloadFailure, resumeData: Data? = nil) {
        delegate?.downloadFailed(failure, resumeData: resumeData)
    }
}

/// An engine that answers from a table and can be told to fail or to take its time.
actor FakeEngine: KokoroSynthesizing {
    struct Call: Equatable { let text: String; let voice: String; let speed: Double }
    var calls: [Call] = []
    var loads: [URL] = []
    var unloads = 0
    var failLoad: String?
    var failSynthesis: KokoroEngineError?
    var gate: CheckedContinuation<Void, Never>?
    var holdNext = false
    var loadGate: CheckedContinuation<Void, Never>?
    var holdLoadNext = false

    func load(root: URL, cache: URL) async throws {
        loads.append(root)
        if holdLoadNext {
            holdLoadNext = false
            await withCheckedContinuation { loadGate = $0 }
        }
        if let failLoad { throw KokoroEngineError.load(failLoad) }
    }
    func synthesize(_ text: String, voice: String, speed: Double) async throws -> [Float] {
        calls.append(Call(text: text, voice: voice, speed: speed))
        if holdNext {
            holdNext = false
            await withCheckedContinuation { gate = $0 }
            try Task.checkCancellation()
        }
        if let failSynthesis { throw failSynthesis }
        return [Float](repeating: 0.1, count: text.count)
    }
    func unload() { unloads += 1 }
    func release() {
        gate?.resume()
        gate = nil
    }
    func hold() { holdNext = true }
    /// The same for the load, so a test can unload while the models are still arriving.
    func holdLoad() { holdLoadNext = true }
    func releaseLoad() {
        loadGate?.resume()
        loadGate = nil
    }
    func setFailLoad(_ s: String?) { failLoad = s }
    func setFailSynthesis(_ e: KokoroEngineError?) { failSynthesis = e }
}

/// Plays nothing and lets the test say when the buffer has been heard.
@MainActor final class FakePlayback: KokoroPlaying {
    struct Played { let samples: [Float]; let volume: Double; let rate: Double }
    var played: [Played] = []
    var stops = 0
    private var completion: (@MainActor () -> Void)?
    func play(
        _ samples: [Float], volume: Double, rate: Double, completion: @escaping @MainActor () -> Void
    ) {
        played.append(Played(samples: samples, volume: volume, rate: rate))
        self.completion = completion
    }
    var volumes: [Double] = []
    func setVolume(_ volume: Double) { volumes.append(volume) }
    /// Counts the stop and keeps the completion: a real player can call back after one,
    /// and it must be the provider's own generation guard that swallows it.
    func stop() { stops += 1 }
    func finish() {
        let c = completion
        completion = nil
        c?()
    }
}
