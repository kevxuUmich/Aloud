import AloudUI
import AppKit
import SwiftUI

/// The Now Playing card's plate: the waveform in white on the accent colour, the
/// same plate the clipboard panel draws. Rendered once at launch and handed to
/// `NowPlaying`, so the card has a picture rather than a grey square.
enum NowPlayingArtwork {
    @MainActor static func make() -> NSImage? {
        let plate = RoundedRectangle(cornerRadius: Radius.plate, style: .continuous)
            .fill(Ink.plate)
            .frame(width: Size.clipboardPlate, height: Size.clipboardPlate)
            .overlay {
                Image(systemName: "waveform")
                    .resizable().scaledToFit()
                    .frame(width: Size.clipboardGlyph, height: Size.clipboardGlyph)
                    .foregroundStyle(Ink.plateGlyph)
            }
        let renderer = ImageRenderer(content: plate)
        renderer.scale = NSScreen.main?.backingScaleFactor ?? 1
        return renderer.nsImage
    }
}
