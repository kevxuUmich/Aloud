import AloudUI
import AppKit
import Prose
import Speech
import SwiftUI
import Vault

@main
struct AloudApp: App {
    static let args = CommandLine.arguments
    static let showGallery = args.contains("--gallery")
    static var sayFile: URL? {
        guard let i = args.firstIndex(of: "--say"), i + 1 < args.count else { return nil }
        return URL(fileURLWithPath: args[i + 1])
    }

    @MainActor static var sayPlayer: Player?

    init() {
        if let file = Self.sayFile { Task { @MainActor in try? await Self.say(file) } }
    }

    var body: some Scene {
        WindowGroup("Aloud") {
            if Self.showGallery { Gallery() } else { Text("Aloud") }
        }
        .defaultSize(Size.minWindow)
    }

    @MainActor static func say(_ file: URL) async throws {
        let kind: SourceKind = DocumentType(url: file) == .markdown ? .markdown : .plainText
        let script = try await Extraction().script(for: file, kind: kind, options: .default)
        let player = Player(provider: AppleVoiceProvider())
        player.load(script, at: 0)
        player.onSentence = { print(script.sentences[$0].text) }
        player.onFinished = { NSApp.terminate(nil) }
        sayPlayer = player
        player.play()
    }
}
