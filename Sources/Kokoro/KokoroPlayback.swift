import AVFoundation
import Foundation

/// Queues buffers of samples and says when each has been heard, so a fake can stand in.
@MainActor
public protocol KokoroPlaying: AnyObject {
    /// Queues one buffer behind whatever is queued, starting the device if it is idle, and
    /// calls back once that buffer has been heard. Nothing already queued is touched, so
    /// a sentence can be heard chunk by chunk as its chunks are rendered.
    func enqueue(_ samples: [Float], completion: @escaping @MainActor () -> Void)
    /// The level of whatever is playing and queued, changed where it stands.
    func setVolume(_ volume: Double)
    /// The time stretch of whatever is playing and queued, changed where it stands: how a
    /// speed the model did not render is made up, and how a speed change mid-sentence is
    /// heard without rendering the sentence again. 1 is the samples as rendered.
    func setRate(_ rate: Double)
    /// Drops everything queued.
    func stop()
    /// Stops and gives the audio device back, for a reader who has picked another engine
    /// and will not be spoken to by this one again until they pick it back.
    func shutdown()
}

/// An audio engine with one player node at the model's 24 kHz mono, through a time
/// stretch. Buffers queue on the node in the order they arrive. A device change stops the
/// engine out from under it; the next `enqueue` restarts it on the new device. The pause
/// on that same change is the app model's, through `OutputDeviceWatcher`, not this
/// class's.
@MainActor
public final class KokoroPlayback: KokoroPlaying {
    /// Nonisolated so `KokoroEngine`, a plain actor, can check the SDK's output against
    /// it without crossing to the main actor for a constant.
    public nonisolated static let sampleRate: Double = 24000

    private let engine = AVAudioEngine()
    private let node = AVAudioPlayerNode()
    /// The speed the model could not deliver, and the rest of a sentence at a speed the
    /// reader changed to mid-way. It sits between the player node and the mixer at all
    /// times, at rate 1 whenever nothing is being stretched, so the graph does not have
    /// to be rewired when the reader changes speed.
    private let timePitch = AVAudioUnitTimePitch()
    private let format = AVAudioFormat(standardFormatWithSampleRate: KokoroPlayback.sampleRate, channels: 1)!
    /// A completion from a buffer that was dropped by a stop is not one the caller wants.
    private var generation = 0

    public init() {
        engine.attach(node)
        engine.attach(timePitch)
        engine.connect(node, to: timePitch, format: format)
        engine.connect(timePitch, to: engine.mainMixerNode, format: format)
    }

    public func enqueue(_ samples: [Float], completion: @escaping @MainActor () -> Void) {
        let gen = generation
        // An empty buffer is heard at once. The caller keeps its own order and never
        // hands one over, so this is only a guard against scheduling nothing.
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
        node.scheduleBuffer(buffer, completionCallbackType: .dataPlayedBack) { _ in
            Task { @MainActor [weak self] in
                guard let self, gen == self.generation else { return }
                completion()
            }
        }
        // A no-op on a node already playing; what it is for is the first buffer after a
        // stop or a device change, when the node is idle.
        node.play()
    }

    public func setVolume(_ volume: Double) { node.volume = Self.level(volume) }

    public func setRate(_ rate: Double) { timePitch.rate = Self.stretch(rate) }

    public func stop() {
        generation += 1
        node.stop()
    }

    /// The audio engine stays running once started, which keeps the HAL awake for the
    /// life of the process: a measurable idle draw on a laptop for an app that spends
    /// most of its time paused. `play` starts it again when it is next needed.
    public func shutdown() {
        stop()
        engine.stop()
    }

    /// The level, 0 to 1, with anything that is not a number read as full: Swift's
    /// `min` and `max` pass a NaN straight through and `AVAudioPlayerNode` would take it.
    static func level(_ volume: Double) -> Float {
        guard volume.isFinite else { return 1 }
        return Float(min(max(volume, 0), 1))
    }

    /// What `AVAudioUnitTimePitch.rate` accepts, as its documentation gives it. A value
    /// outside this is not clamped by the unit, it is rejected.
    static let stretchRange: ClosedRange<Double> = 1.0 / 32.0...32.0

    /// The time stretch, inside what the unit accepts, with anything that is not a
    /// number read as no stretch at all.
    static func stretch(_ rate: Double) -> Float {
        guard rate.isFinite else { return 1 }
        return Float(min(max(rate, Self.stretchRange.lowerBound), Self.stretchRange.upperBound))
    }
}
