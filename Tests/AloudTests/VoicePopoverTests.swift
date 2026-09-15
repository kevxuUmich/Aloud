import AloudUI
import Kokoro
import Testing

@testable import Aloud

/// The two pure functions that stand between the store's state and the section header:
/// what the banner shows, and whether the rows are dimmed. Every state is listed, so a
/// sixth case added to `KokoroStoreState` fails to compile here rather than falling
/// quietly into a default.
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
}
