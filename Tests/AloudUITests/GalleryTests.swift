import SwiftUI
import Testing

@testable import AloudUI

@Suite @MainActor struct GalleryTests {
    @Test func galleryBuilds() {
        let g = Gallery()
        _ = g.body
        #expect(Gallery.sections.count >= 8)
    }
}
