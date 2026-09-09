import AloudUI
import KeyboardShortcuts
import ServiceManagement
import Speech
import SwiftUI
import Vault

/// Everything Settings holds already belongs to something else - the roots to
/// `RootStore`, the voice and the speed to the player, the hotkey to `KeyboardShortcuts`.
/// This is the one window that shows them together, and it writes through `AppModel` so
/// the single-writer rules the model keeps still hold.
struct SettingsView: View {
    @Bindable var model: AppModel
    @AppStorage("skipCode") private var skipCode = true
    @AppStorage("showMenuBar") private var showMenuBar = true

    var body: some View {
        Form {
            Section("Vault folders") {
                ForEach(model.roots, id: \.path) { url in
                    HStack {
                        Text(url.lastPathComponent)
                        if model.noteFolder == url {
                            Text("New notes go here").font(Type.caption).foregroundStyle(Ink.soft)
                        }
                        Spacer()
                        Button("Use for new notes") { model.setNoteFolder(url) }
                            .disabled(model.noteFolder == url)
                        Button("Remove", role: .destructive) { model.removeRoot(url) }
                    }
                }
                // A root whose bookmark will not resolve is named from its last known
                // path and offered a new one, rather than being dropped: the folder may
                // be on a volume that is merely unmounted. Removing it is the reader's
                // call, so it is offered too, and identity is the store's index rather
                // than the path, which a migrated root may share with another.
                ForEach(model.unreachable) { root in
                    HStack {
                        Label(
                            "\(URL(fileURLWithPath: root.path).lastPathComponent) is not reachable",
                            systemImage: "exclamationmark.triangle")
                        Spacer()
                        Button("Locate...") { model.locate(root) }
                        Button("Remove", role: .destructive) {
                            model.removeUnreachable(index: root.index)
                        }
                    }
                }
                Button("Add Folder...") { model.pickRootFolder() }
            }
            Section("Voice") {
                Picker(
                    "Default voice",
                    selection: Binding(
                        get: { model.player.voice?.id ?? "" },
                        set: { id in
                            if let v = model.provider.voices.first(where: { $0.id == id }) {
                                model.pickVoice(v)
                            }
                        })
                ) {
                    ForEach(
                        VoiceGroups.group(
                            model.provider.voices, currentLanguage: VoiceGroups.currentLanguage)
                    ) { group in
                        Section(group.name) {
                            ForEach(group.voices) { v in Text(v.name).tag(v.id) }
                        }
                    }
                }
                Picker(
                    "Default speed",
                    selection: Binding(get: { model.player.rate }, set: { model.setRate($0) })
                ) {
                    ForEach(Rate.allCases, id: \.self) { Text($0.label).tag($0) }
                }
            }
            Section("Reading") {
                Toggle("Skip code blocks in Markdown", isOn: $skipCode)
            }
            Section("Hotkey") {
                KeyboardShortcuts.Recorder("Paste and play:", name: .pasteAndPlay)
            }
            Section("General") {
                Toggle("Show in the menu bar", isOn: $showMenuBar)
                Toggle(
                    "Launch at login",
                    isOn: Binding(
                        get: { model.launchAtLogin }, set: { model.setLaunchAtLogin($0) }))
            }
        }
        .formStyle(.grouped)
        .frame(width: Size.settingsWidth)
        // Skipping code blocks changes what the text is, so the document already open
        // has to be extracted again; the cache is keyed by the options, so it misses of
        // its own accord and nothing needs invalidating.
        .onChange(of: skipCode) { model.reloadCurrent() }
    }
}
