import AloudUI
import SwiftUI

@main
struct AloudApp: App {
    static let showGallery = CommandLine.arguments.contains("--gallery")
    var body: some Scene {
        WindowGroup("Aloud") {
            if Self.showGallery { Gallery() } else { Text("Aloud") }
        }
        .defaultSize(Size.minWindow)
    }
}
