import AVFoundation
import Foundation

/// Plays one buffer of samples and says when it has been heard, so a fake can stand in.
@MainActor
public protocol KokoroPlaying: AnyObject {
    func play(_ samples: [Float], volume: Double, completion: @escaping @MainActor () -> Void)
    func stop()
}

/// An audio engine with one player node at the model's 24 kHz mono. A new buffer
/// replaces whatever is playing. The engine is restarted when the output device
/// changes, so an unplugged headphone set does not leave it silent.
@MainActor
public final class KokoroPlayback: KokoroPlaying {
    public static let sampleRate: Double = 24000

    private let engine = AVAudioEngine()
    private let node = AVAudioPlayerNode()
    private let format = AVAudioFormat(standardFormatWithSampleRate: KokoroPlayback.sampleRate, channels: 1)!
    /// A completion from a buffer that was replaced or stopped is not the current one's.
    private var generation = 0
    /// A `deinit` is nonisolated even on a `@MainActor` type and cannot read an
    /// isolated property, so the token is held outside the actor's isolation. It is
    /// written once, in `init()`, and read once, in `deinit`, so there is no second
    /// thread to race.
    private nonisolated(unsafe) var observer: (any NSObjectProtocol)?

    public init() {
        engine.attach(node)
        engine.connect(node, to: engine.mainMixerNode, format: format)
        observer = NotificationCenter.default.addObserver(
            forName: .AVAudioEngineConfigurationChange, object: engine, queue: .main
        ) { [weak self] _ in
            // The engine has stopped itself; the next play starts it again with the new
            // device. Whatever was in the air is lost, and the model pauses on the same
            // change, so nothing is resumed here.
            MainActor.assumeIsolated { self?.generation += 1 }
        }
    }

    deinit {
        if let observer { NotificationCenter.default.removeObserver(observer) }
    }

    public func play(_ samples: [Float], volume: Double, completion: @escaping @MainActor () -> Void) {
        node.stop()
        generation += 1
        let gen = generation
        guard !samples.isEmpty else {
            completion()
            return
        }
        if !engine.isRunning {
            do {
                try engine.start()
            } catch {
                completion()
                return
            }
        }
        guard
            let buffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: AVAudioFrameCount(samples.count)),
            let channel = buffer.floatChannelData?[0]
        else {
            completion()
            return
        }
        samples.withUnsafeBufferPointer { channel.update(from: $0.baseAddress!, count: samples.count) }
        buffer.frameLength = AVAudioFrameCount(samples.count)
        node.volume = Float(min(max(volume, 0), 1))
        node.scheduleBuffer(buffer, completionCallbackType: .dataPlayedBack) { _ in
            Task { @MainActor [weak self] in
                guard let self, gen == self.generation else { return }
                completion()
            }
        }
        node.play()
    }

    public func stop() {
        generation += 1
        node.stop()
    }
}
