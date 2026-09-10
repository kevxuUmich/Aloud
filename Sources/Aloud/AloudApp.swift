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
    /// The skip interval as the menu says it, so the titles cannot drift from the step.
    static let skipStep = Int(Player.skipSeconds)
    /// The one window's id, which is also what the menu bar's Open Aloud reopens.
    static let mainWindowID = "main"

    @AppStorage("showMenuBar") private var showMenuBar = true
    /// The reader's text size, shared with the reader through the one key, so the
    /// View menu's steps and the toolbar's menu move the same setting.
    @AppStorage(ReaderSize.key) private var readerSize = Type.readerDefaultIndex

    @State private var model: AppModel
    /// The clipboard panel's owner, alive with the window closed: it is not a scene,
    /// so it is made here beside the model rather than in the body.
    @State private var clipboardPanel: ClipboardPanelController

    init() {
        if let file = Self.sayFile { Task { @MainActor in try? await Self.say(file) } }
        // One model, built into a local and handed to both: reading `_model.wrappedValue`
        // in the second initialiser would capture a `self` that is not initialised yet.
        let m = MainActor.assumeIsolated {
            AppModel(
                provider: Self.args.contains("--silent") ? FakeVoiceProvider() : AppleVoiceProvider())
        }
        _model = State(initialValue: m)
        _clipboardPanel = State(initialValue: MainActor.assumeIsolated { ClipboardPanelController(model: m) })
    }

    var body: some Scene {
        Window("Aloud", id: Self.mainWindowID) {
            if Self.showGallery { Gallery() } else { RootView(model: model) }
        }
        .defaultSize(Size.minWindow)
        .commands {
            // Bare Cmd+V is the library's own paste and needs the library to have focus.
            // Cmd+Shift+V is the always-available form, wherever the focus is.
            // One window: the model's listeners, the Now Playing mirror and the device
            // watcher are all process-wide, and a second window would be a second
            // library looking at the same player.
            CommandGroup(replacing: .newItem) {}
            // Cmd+S while the editor is open. The reader owns the draft, so the
            // command asks for a save rather than performing one.
            CommandGroup(replacing: .saveItem) {
                Button("Save") { model.saveRequested += 1 }
                    .keyboardShortcut("s")
                    .disabled(!model.isEditing)
            }
            CommandGroup(after: .pasteboard) {
                Button("New Note from Clipboard") { model.pasteNote() }
                    .keyboardShortcut("v", modifiers: [.command, .shift])
            }
            CommandMenu("View") {
                Button("Smaller Text") { readerSize = ReaderSize.smaller(readerSize) }
                    .keyboardShortcut("-", modifiers: .command)
                    .disabled(ReaderSize.clamp(readerSize) == 0)
                Button("Larger Text") { readerSize = ReaderSize.larger(readerSize) }
                    .keyboardShortcut("=", modifiers: .command)
                    .disabled(ReaderSize.clamp(readerSize) == ReaderSize.last)
            }
            CommandMenu("Playback") {
                // Space, left and right are bare keys, so while the reader's editor has
                // focus they would be typed characters and caret moves rather than
                // transport. Disabling the command is what hands them back to the field.
                Button(model.player.isPlaying ? "Pause" : "Play") { model.player.toggle() }
                    .keyboardShortcut(KeyEquivalent(" "), modifiers: [])
                    .disabled(model.isEditing)
                Button("Back \(Self.skipStep) seconds") { model.player.skip(seconds: -Player.skipSeconds) }
                    .keyboardShortcut(.leftArrow, modifiers: [])
                    .disabled(model.isEditing)
                Button("Forward \(Self.skipStep) seconds") { model.player.skip(seconds: Player.skipSeconds) }
                    .keyboardShortcut(.rightArrow, modifiers: [])
                    .disabled(model.isEditing)
                Button("Faster") { model.setRate(model.player.rate.next) }
                    .keyboardShortcut("]", modifiers: .command)
            }
        }

        // The same model, so the bar is the window's player rather than a second one.
        MenuBarExtra(isInserted: $showMenuBar) {
            MenuBarPanel(model: model)
        } label: {
            // The mark, as a template image so it takes the bar's tint. A drawn shape
            // has no symbol effect, so the bar no longer pulses while playing; the panel
            // under it says play or pause.
            markLabel
                .opacity(model.current == nil ? Motion.dimmed : 1)
                .accessibilityLabel("Aloud")
        }
        .menuBarExtraStyle(.window)

        // Cmd+, and the app menu's Settings item come with the scene.
        Settings {
            SettingsView(model: model)
        }
    }

    /// The rendered mark, with the symbol as a fallback should rendering fail.
    @ViewBuilder private var markLabel: some View {
        if let image = MarkImage.menuBar {
            Image(nsImage: image)
        } else {
            Image(systemName: "waveform")
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
