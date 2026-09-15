import SwiftUI
import Testing

@testable import AloudUI

@Suite @MainActor struct DownloadBannerTests {
    /// Every phase builds, and the strings the app shows are the spec's.
    @Test func everyPhaseBuildsAndTheCopyIsTheSpecs() {
        for phase in [
            DownloadBanner.Phase.idle(Copy.kokoroCaption), .progress(0.4), .busy(Copy.kokoroInstalling),
            .failed("No internet connection."),
        ] {
            _ = DownloadBanner(title: Copy.kokoroSection, phase: phase, onCancel: {}, onRetry: {}).body
        }
        #expect(Copy.kokoroSection == "Kokoro")
        #expect(Copy.kokoroCaption.hasPrefix("Seven voices, one download of about "))
        #expect(Copy.kokoroCaption.hasSuffix(" MB, runs on your Mac."))
        #expect(
            Copy.cancel == "Cancel" && Copy.retry == "Retry" && Copy.download == "Download"
                && Copy.remove == "Remove")
        #expect(Copy.kokoroInstalled(version: "1", size: "159 MB") == "Version 1, 159 MB")
    }

    @Test func aBusyOrDimmedRowBuilds() {
        _ =
            VoiceRow(
                name: "Bella", region: "United States", quality: "Premium", isSelected: true, isBusy: true,
                onPreview: {}, onPick: {}
            ).body
        _ =
            VoiceRow(
                name: "Bella", region: "United States", quality: "Premium", badge: "159 MB",
                isSelected: false,
                isInstalled: false, isDimmed: true, onPreview: {}, onPick: {}
            ).body
        #expect(Gallery.sections.contains("DownloadBanner"))
    }
}
