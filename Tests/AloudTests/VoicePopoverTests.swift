import AloudUI
import Kokoro
import Testing

@testable import Aloud

/// The pure functions that stand between the store's state and what a reader is shown:
/// the banner's phase, whether the rows are dimmed, and the Settings line. The tables
/// list every state, and the functions they drive are exhaustive switches, so a sixth
/// case added to `KokoroStoreState` fails to compile in `VoicePopover` and
/// `SettingsView` rather than falling quietly into a default. The tables themselves are
/// array literals and would still compile: what they pin is the answer, not the shape.
@Suite @MainActor struct VoicePopoverTests {
    static let states: [(KokoroStoreState, DownloadBanner.Phase, Bool)] = [
        (.absent, .idle(Copy.kokoroCaption), false),
        (.downloading(0.4), .progress(0.4), true),
        (.installing, .busy(Copy.kokoroInstalling), true),
        (.installed(version: "1", bytes: 1), .idle(""), false),
        (.failed("No internet connection."), .failed("No internet connection."), false),
    ]

    @Test func everyStateHasItsBannerPhase() {
        for (state, phase, _) in Self.states {
            #expect(VoicePopover.phase(state) == phase, "\(state)")
        }
    }

    /// Busy is the download and the install, and nothing else: the rows are dimmed only
    /// while the one download is in flight.
    @Test func onlyTheDownloadAndTheInstallAreBusy() {
        for (state, _, busy) in Self.states {
            #expect(VoicePopover.isBusy(state) == busy, "\(state)")
        }
    }

    /// The rows are the catalogue's voices only once the model is here, and that is read
    /// off the state rather than off the flag beside it.
    @Test func onlyInstalledCountsAsInstalled() {
        for (state, _, _) in Self.states {
            let expected = state == .installed(version: "1", bytes: 1)
            #expect(VoicePopover.isInstalled(state) == expected, "\(state)")
        }
    }

    /// The one line the Voice section in Settings shows about the model, over every
    /// state. The installed row is the one with something to get wrong: the size goes
    /// through the same whole-megabyte helper as the picker's badge.
    static let settingsLines: [(KokoroStoreState, String)] = [
        (.absent, Copy.kokoroAbsent),
        (.downloading(0.42), 0.42.formatted(.percent.precision(.fractionLength(0)))),
        (.installing, Copy.kokoroInstalling),
        (.installed(version: "2", bytes: 169_000_000), "Version 2, 169 MB"),
        (.failed(KokoroStore.mismatchMessage), KokoroStore.mismatchMessage),
    ]

    @Test func everyStateHasItsSettingsLine() {
        for (state, line) in Self.settingsLines {
            #expect(SettingsView.kokoroStatus(state) == line, "\(state)")
        }
    }
}
