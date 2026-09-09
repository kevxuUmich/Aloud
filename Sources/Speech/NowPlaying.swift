import Foundation
import MediaPlayer
import Observation

public protocol NowPlayingCenter: AnyObject {
    func set(info: [String: Any])
    func set(playing: Bool)
}

public protocol RemoteCommands: AnyObject {
    func bind(
        play: @escaping () -> Void, pause: @escaping () -> Void, toggle: @escaping () -> Void,
        skipForward: @escaping () -> Void, skipBackward: @escaping () -> Void)
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
    public func bind(
        play: @escaping () -> Void, pause: @escaping () -> Void, toggle: @escaping () -> Void,
        skipForward: @escaping () -> Void, skipBackward: @escaping () -> Void
    ) {
        let c = MPRemoteCommandCenter.shared()
        c.playCommand.addTarget { _ in
            play()
            return .success
        }
        c.pauseCommand.addTarget { _ in
            pause()
            return .success
        }
        c.togglePlayPauseCommand.addTarget { _ in
            toggle()
            return .success
        }
        c.skipForwardCommand.preferredIntervals = [NSNumber(value: Player.skipSeconds)]
        c.skipForwardCommand.addTarget { _ in
            skipForward()
            return .success
        }
        c.skipBackwardCommand.preferredIntervals = [NSNumber(value: Player.skipSeconds)]
        c.skipBackwardCommand.addTarget { _ in
            skipBackward()
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

    /// Re-pushes whenever the player's observed state changes.
    private func observe() {
        observation = Task { [weak self] in
            while let self, !Task.isCancelled {
                await withCheckedContinuation { (c: CheckedContinuation<Void, Never>) in
                    withObservationTracking {
                        _ = self.player.isPlaying
                        _ = self.player.sentenceIndex
                        _ = self.player.rate
                    } onChange: {
                        c.resume()
                    }
                }
                self.push()
            }
        }
    }
}
