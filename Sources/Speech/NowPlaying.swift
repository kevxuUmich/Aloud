import Foundation
import MediaPlayer
import Observation

public protocol NowPlayingCenter: AnyObject {
    func set(info: [String: Any])
    func set(playing: Bool)
}

/// The handlers reach the player, which is on the main actor, and the system calls a
/// media key back on a queue of its own choosing, so the isolation is part of the
/// signature rather than something each implementer remembers.
public protocol RemoteCommands: AnyObject {
    func bind(
        play: @escaping @Sendable @MainActor () -> Void,
        pause: @escaping @Sendable @MainActor () -> Void,
        toggle: @escaping @Sendable @MainActor () -> Void,
        skipForward: @escaping @Sendable @MainActor () -> Void,
        skipBackward: @escaping @Sendable @MainActor () -> Void)
}

/// The real Now Playing panel. The keys are spelled here rather than at the call
/// site so a fake never has to know `MPMediaItemPropertyTitle`.
public final class SystemNowPlayingCenter: NowPlayingCenter {
    public init() {}
    public func set(info: [String: Any]) {
        var mp: [String: Any] = [:]
        if let t = info["title"] { mp[MPMediaItemPropertyTitle] = t }
        if let d = info["duration"] { mp[MPMediaItemPropertyPlaybackDuration] = d }
        if let e = info["elapsed"] { mp[MPNowPlayingInfoPropertyElapsedPlaybackTime] = e }
        if let r = info["rate"] { mp[MPNowPlayingInfoPropertyPlaybackRate] = r }
        MPNowPlayingInfoCenter.default().nowPlayingInfo = mp
    }
    public func set(playing: Bool) {
        MPNowPlayingInfoCenter.default().playbackState = playing ? .playing : .paused
    }
}

/// The media keys and the Control Centre transport.
public final class SystemRemoteCommands: RemoteCommands {
    public init() {}
    /// Every target hops to the main actor the way `OutputDeviceWatcher`'s caller does:
    /// MediaPlayer promises no particular queue, and a handler that assumed one would
    /// trap in a listener's hands rather than in a test's. The status is answered for
    /// the command as taken, which it is: the hop cannot fail, only land a moment later.
    public func bind(
        play: @escaping @Sendable @MainActor () -> Void,
        pause: @escaping @Sendable @MainActor () -> Void,
        toggle: @escaping @Sendable @MainActor () -> Void,
        skipForward: @escaping @Sendable @MainActor () -> Void,
        skipBackward: @escaping @Sendable @MainActor () -> Void
    ) {
        let c = MPRemoteCommandCenter.shared()
        c.playCommand.addTarget { _ in
            Task { @MainActor in play() }
            return .success
        }
        c.pauseCommand.addTarget { _ in
            Task { @MainActor in pause() }
            return .success
        }
        c.togglePlayPauseCommand.addTarget { _ in
            Task { @MainActor in toggle() }
            return .success
        }
        c.skipForwardCommand.preferredIntervals = [NSNumber(value: Player.skipSeconds)]
        c.skipForwardCommand.addTarget { _ in
            Task { @MainActor in skipForward() }
            return .success
        }
        c.skipBackwardCommand.preferredIntervals = [NSNumber(value: Player.skipSeconds)]
        c.skipBackwardCommand.addTarget { _ in
            Task { @MainActor in skipBackward() }
            return .success
        }
    }
}

/// Mirrors the player into the system's Now Playing and answers the media keys.
@MainActor
public final class NowPlaying {
    private let player: Player
    private let center: any NowPlayingCenter
    private var title: String?
    private var observation: Task<Void, Never>?

    public init(
        player: Player, center: any NowPlayingCenter = SystemNowPlayingCenter(),
        commands: any RemoteCommands = SystemRemoteCommands()
    ) {
        self.player = player
        self.center = center
        commands.bind(
            play: { [weak self] in
                self?.player.play()
                self?.push()
            },
            pause: { [weak self] in
                self?.player.pause()
                self?.push()
            },
            toggle: { [weak self] in
                self?.player.toggle()
                self?.push()
            },
            skipForward: { [weak self] in
                self?.player.skip(seconds: Player.skipSeconds)
                self?.push()
            },
            skipBackward: { [weak self] in
                self?.player.skip(seconds: -Player.skipSeconds)
                self?.push()
            })
        observe()
    }

    deinit { observation?.cancel() }

    public func update(title: String?) {
        self.title = title
        push()
    }

    /// Reads the player and writes the centre, and only ever in that direction. The
    /// observation loop below re-runs this whenever the observed state changes, so a
    /// write back into any observed property here would wake the loop that called it
    /// and spin forever. Nothing in this method may touch player state.
    private func push() {
        center.set(info: [
            "title": title ?? "Aloud",
            "duration": player.timeline.total.seconds,
            "elapsed": player.elapsed.seconds,
            "rate": player.isPlaying ? player.rate.factor : 0,
        ])
        center.set(playing: player.isPlaying)
    }

    /// Re-pushes whenever the player's observed state changes. `Observations` is used
    /// rather than a hand-rolled `withObservationTracking` loop because the loop's
    /// `while let self` held `self` across every suspension: `deinit` could never run,
    /// so cancellation had nothing to cancel it from and the task outlived its owner.
    /// Here `self` is only bound for the length of one push.
    private func observe() {
        observation = Task { [weak self] in
            let stream = Observations { [weak self] in
                (
                    self?.player.isPlaying, self?.player.sentenceIndex, self?.player.rate,
                    self?.player.timeline.total
                )
            }
            for await _ in stream {
                guard let self else { return }
                self.push()
            }
        }
    }
}
