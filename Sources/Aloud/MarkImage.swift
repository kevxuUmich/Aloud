import AloudUI
import AppKit
import SwiftUI

/// The mark as a template image for the menu bar, rendered once: the status item
/// takes an image, and a template one takes the bar's own tint, dark or light.
enum MarkImage {
    @MainActor static let menuBar: NSImage? = {
        let glyph = ApertureGlyph()
            .frame(width: Size.menuBarGlyph, height: Size.menuBarGlyph)
            .foregroundStyle(Ink.thumbInk)
        let renderer = ImageRenderer(content: glyph)
        renderer.scale = NSScreen.main?.backingScaleFactor ?? 1
        let image = renderer.nsImage
        image?.isTemplate = true
        return image
    }()
}
