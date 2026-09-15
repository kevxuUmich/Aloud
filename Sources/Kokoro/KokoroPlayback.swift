import AVFoundation
import Foundation

/// Plays one buffer of samples and says when it has been heard, so a fake can stand in.
@MainActor
public protocol KokoroPlaying: AnyObject {
    /// `rate` is the time stretch to apply on the way out, which is how a speed the
    /// model cannot deliver is made up. 1 is the samples as they were rendered.
    func play(_ samples: [Float], volume: Double, rate: Double, completion: @escaping @MainActor () -> Void)
    /// The level of whatever is playing, changed where it stands. Nothing is re-rendered.
    func setVolume(_ volume: Double)
    func stop()
    /// Stops and gives the audio device back, for a reader who has picked another engine
    /// and will not be spoken to by this one again until they pick it back.
    func shutdown()
}

/// An audio engine with one player node at the model's 24 kHz mono, through a time
/// stretch. A new buffer replaces whatever is playing. A device change stops the engine
/// out from under it; the next `play` restarts it on the new device. The pause on that
/// same change is the app model's, through `OutputDeviceWatcher`, not this class's.
@MainActor
public final class KokoroPlayback: KokoroPlaying {
    /// Nonisolated so `KokoroEngine`, a plain actor, can check the SDK's output against
    /// it without crossing to the main actor for a constant.
    public nonisolated static let sampleRate: Double = 24000

    private let engine = AVAudioEngine()
    private let node = AVAudioPlayerNode()
    /// The speed the model could not deliver. It sits between the player node and the
    /// mixer at all times, at rate 1 whenever nothing is being stretched, so the graph
    /// does not have to be rewired when the reader changes speed mid-sentence.
    private let timePitch = AVAudioUnitTimePitch()
    private let format = AVAudioFormat(standardFormatWithSampleRate: KokoroPlayback.sampleRate, channels: 1)!
    /// A completion from a buffer that was replaced or stopped is not the current one's.
    private var generation = 0

    public init() {
        engine.attach(node)
        engine.attach(timePitch)
        engine.connect(node, to: timePitch, format: format)
        engine.connect(timePitch, to: engine.mainMixerNode, format: format)
    }

    public func play(
        _ samples: [Float], volume: Double, rate: Double, completion: @escaping @MainActor () -> Void
    ) {
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
        node.volume = Self.level(volume)
        timePitch.rate = Self.stretch(rate)
        node.scheduleBuffer(buffer, completionCallbackType: .dataPlayedBack) { _ in
            Task { @MainActor [weak self] in
                guard let self, gen == self.generation else { return }
                completion()
            }
        }
        node.play()
    }

    public func setVolume(_ volume: Double) { node.volume = Self.level(volume) }

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
