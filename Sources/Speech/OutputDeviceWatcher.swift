import CoreAudio
import Foundation

/// Fires when the default output device changes: headphones unplugged, AirPods gone.
public final class OutputDeviceWatcher: @unchecked Sendable {
    private var address = AudioObjectPropertyAddress(
        mSelector: kAudioHardwarePropertyDefaultOutputDevice,
        mScope: kAudioObjectPropertyScopeGlobal,
        mElement: kAudioObjectPropertyElementMain)
    private let queue = DispatchQueue(label: "design.kevxu.aloud.output-device")
    private var block: AudioObjectPropertyListenerBlock?
    private var stopped = false

    public init(onChange: @escaping @Sendable () -> Void) {
        let block: AudioObjectPropertyListenerBlock = { _, _ in onChange() }
        self.block = block
        AudioObjectAddPropertyListenerBlock(
            AudioObjectID(kAudioObjectSystemObject), &address, queue, block)
    }

    public func stop() {
        queue.sync {
            guard !stopped, let block else { return }
            stopped = true
            AudioObjectRemovePropertyListenerBlock(
                AudioObjectID(kAudioObjectSystemObject), &address, queue, block)
        }
    }

    deinit { stop() }
}
