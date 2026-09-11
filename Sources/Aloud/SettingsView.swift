import AloudUI
import AppKit
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
            // Where a new note lands. Aloud's own folder by default, so pasting works
            // with nothing attached; any folder can take its place, one inside iCloud
            // Drive included, which is how notes reach another Mac.
            Section("Notes") {
                LabeledContent("New notes are saved in") {
                    Text(model.noteFolder?.lastPathComponent ?? "Nowhere: Aloud's folder could not be made")
                        .foregroundStyle(Ink.soft)
                }
                HStack {
                    Button("Change...") { model.chooseNoteFolder() }
                    Button("Use Aloud's Folder") { model.useBuiltInNotes() }
                        .disabled(model.usesBuiltInNotes || model.notesFolder == nil)
                    Spacer()
                    if let folder = model.noteFolder {
                        Button("Show in Finder") {
                            NSWorkspace.shared.activateFileViewerSelecting([folder])
                        }
                    }
                }
            }
            Section("Vault folders") {
                if let notes = model.notesFolder {
                    HStack {
                        Text(notes.lastPathComponent)
                        Text("Built in").font(Type.caption).foregroundStyle(Ink.soft)
                        if model.usesBuiltInNotes {
                            Text("New notes go here").font(Type.caption).foregroundStyle(Ink.soft)
                        }
                        Spacer()
                        Button("Use for new notes") { model.useBuiltInNotes() }
                            .disabled(model.usesBuiltInNotes)
                    }
                }
                ForEach(model.roots, id: \.path) { url in
                    HStack {
                        Text(url.lastPathComponent)
                        if model.noteFolder == url {
                            Text("New notes go here").font(Type.caption).foregroundStyle(Ink.soft)
                        }
                        Spacer()
                        Button("Use for new notes") { model.setNoteFolder(url) }
                            .disabled(model.noteFolder == url)
                        Button("Detach Folder", role: .destructive) { model.removeRoot(url) }
                    }
                }
                // A root whose bookmark will not resolve is named from its last known
                // path and offered a new one, rather than being dropped: the folder may
                // be on a volume that is merely unmounted. Detaching it is the reader's
                // call, so it is offered too, and identity is the store's index rather
                // than the path, which a migrated root may share with another.
                ForEach(model.unreachable) { root in
                    HStack {
                        Label(
                            "\(URL(fileURLWithPath: root.path).lastPathComponent) is not reachable",
                            systemImage: "exclamationmark.triangle")
                        Spacer()
                        Button("Locate...") { model.locate(root) }
                        Button("Detach Folder", role: .destructive) {
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
                            // The names alone would show one "Jamie" for each quality
                            // installed, so any quality above the default is spelled out.
                            ForEach(group.voices) { v in
                                Text(
                                    v.quality == .standard ? v.name : "\(v.name) (\(v.quality.label))"
                                ).tag(v.id)
                            }
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
            // A beat is a beat at any speed, so these are seconds and not a share of
            // the sentence; the paragraph's stands in for the sentence's where a
            // paragraph ends, rather than adding to it.
            Section("Pauses") {
                Stepper(
                    "After a sentence: \(Pauses.label(model.player.pauses.sentence))",
                    value: pauseBinding(\.sentence), in: Pauses.range, step: Pauses.step)
                Stepper(
                    "After a line break: \(Pauses.label(model.player.pauses.paragraph))",
                    value: pauseBinding(\.paragraph), in: Pauses.range, step: Pauses.step)
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

    /// One pause as seconds, written back through the model's single writer.
    private func pauseBinding(_ key: WritableKeyPath<Pauses, Duration>) -> Binding<Double> {
        Binding(
            get: { model.player.pauses[keyPath: key].seconds },
            set: { seconds in
                var p = model.player.pauses
                p[keyPath: key] = .seconds(seconds)
                model.setPauses(p)
            })
    }
}
