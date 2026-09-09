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
            // Bare Cmd+V is the library's own paste and needs the library to have focus.
            // Cmd+Shift+V is the always-available form, wherever the focus is.
            CommandGroup(after: .pasteboard) {
                Button("New Note from Clipboard") { model.pasteNote() }
                    .keyboardShortcut("v", modifiers: [.command, .shift])
            }
            CommandMenu("Playback") {
                // Space, left and right are bare keys, so while the reader's editor has
                // focus they would be typed characters and caret moves rather than
                // transport. Disabling the command is what hands them back to the field.
                Button(model.player.isPlaying ? "Pause" : "Play") { model.player.toggle() }
                    .keyboardShortcut(KeyEquivalent(" "), modifiers: [])
                    .disabled(model.isEditing)
                Button("Back 15 seconds") { model.player.skip(seconds: -Player.skipSeconds) }
                    .keyboardShortcut(.leftArrow, modifiers: [])
                    .disabled(model.isEditing)
                Button("Forward 15 seconds") { model.player.skip(seconds: Player.skipSeconds) }
                    .keyboardShortcut(.rightArrow, modifiers: [])
                    .disabled(model.isEditing)
                Button("Faster") { model.setRate(model.player.rate.next) }
                    .keyboardShortcut("]", modifiers: .command)
            }
        }
    }

    @MainActor static func say(_ file: URL) async throws {
        let kind = SourceKind(DocumentType(url: file) ?? .plainText)
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
