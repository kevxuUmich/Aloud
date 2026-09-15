import AVFoundation
import Foundation

/// Plays one buffer of samples and says when it has been heard, so a fake can stand in.
@MainActor
public protocol KokoroPlaying: AnyObject {
    func play(_ samples: [Float], volume: Double, completion: @escaping @MainActor () -> Void)
    func stop()
}

/// An audio engine with one player node at the model's 24 kHz mono. A new buffer
/// replaces whatever is playing. A device change stops the engine out from under it;
/// the next `play` restarts it on the new device. The pause on that same change is the
/// app model's, through `OutputDeviceWatcher`, not this class's.
@MainActor
public final class KokoroPlayback: KokoroPlaying {
    /// Nonisolated so `KokoroEngine`, a plain actor, can check the SDK's output against
    /// it without crossing to the main actor for a constant.
    public nonisolated static let sampleRate: Double = 24000

    private let engine = AVAudioEngine()
    private let node = AVAudioPlayerNode()
    private let format = AVAudioFormat(standardFormatWithSampleRate: KokoroPlayback.sampleRate, channels: 1)!
    /// A completion from a buffer that was replaced or stopped is not the current one's.
    private var generation = 0

    public init() {
        engine.attach(node)
        engine.connect(node, to: engine.mainMixerNode, format: format)
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
