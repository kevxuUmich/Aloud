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

    @State private var model: AppModel

    init() {
        if let file = Self.sayFile { Task { @MainActor in try? await Self.say(file) } }
        _model = State(
            initialValue: MainActor.assumeIsolated {
                AppModel(
                    provider: Self.args.contains("--silent") ? FakeVoiceProvider() : AppleVoiceProvider())
            })
    }

    var body: some Scene {
        WindowGroup("Aloud") {
            if Self.showGallery { Gallery() } else { RootView(model: model) }
        }
        .defaultSize(Size.minWindow)
        .commands {
            CommandMenu("Playback") {
                Button(model.player.isPlaying ? "Pause" : "Play") { model.player.toggle() }
                    .keyboardShortcut(KeyEquivalent(" "), modifiers: [])
                Button("Back 15 seconds") { model.player.skip(seconds: -Player.skipSeconds) }
                    .keyboardShortcut(.leftArrow, modifiers: [])
                Button("Forward 15 seconds") { model.player.skip(seconds: Player.skipSeconds) }
                    .keyboardShortcut(.rightArrow, modifiers: [])
                Button("Faster") { model.player.rate = model.player.rate.next }
                    .keyboardShortcut("]", modifiers: .command)
            }
        }
    }

    @MainActor static func say(_ file: URL) async throws {
        let kind: SourceKind = DocumentType(url: file) == .markdown ? .markdown : .plainText
        let script = try await Extraction().script(for: file, kind: kind, options: .default)
        guard !script.sentences.isEmpty else {
            print("Nothing to read.")
            NSApp.terminate(nil)
            return
        }
        let player = Player(provider: AppleVoiceProvider())
        player.load(script, at: 0)
        player.onSentence = { print(script.sentences[$0].text) }
        player.onFinished = { NSApp.terminate(nil) }
        sayPlayer = player
        player.play()
    }
}
