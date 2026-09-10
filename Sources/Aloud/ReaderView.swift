import AloudUI
import Prose
import Speech
import SwiftUI
import Vault

struct ReaderView: View {
    var model: AppModel
    var document: Document
    @AppStorage(ReaderSize.key) private var sizeIndex = Type.readerDefaultIndex
    @State private var follow = true
    @State private var editing = false
    @State private var draft = ""
    /// How many saves this reader is waiting on. `AppModel.saveEdit` is what keeps two
    /// writes from overlapping; this is the button's state and nothing more.
    @State private var savesInFlight = 0
    /// True while the source is being read for the editor, which is what keeps a
    /// second click on Edit from starting a second read.
    @State private var loadingDraft = false

    var player: Player { model.player }
    var isCurrent: Bool { model.current?.id == document.id }
    var stepIndex: Int { ReaderSize.clamp(sizeIndex) }

    var body: some View {
        HStack {
            Spacer(minLength: .zero)
            if showsEmptyBody {
                Text(emptyBodyMessage)
                    .font(Type.landingBody)
                    .foregroundStyle(Ink.soft)
                    .padding(Space.xxl)
            } else {
                ReaderTextView(
                    text: editing ? draft : player.script.source,
                    fontSize: Type.readerSizes[stepIndex],
                    sentence: isCurrent
                        ? nsRange(player.script.sentences[safe: player.sentenceIndex]?.range) : nil,
                    word: isCurrent ? nsRange(player.wordRange) : nil,
                    follow: follow && player.isPlaying,
                    editable: editing,
                    onClick: { offset in
                        guard let i = player.script.sentenceIndex(atUTF16Offset: offset) else { return }
                        follow = true
                        player.seek(to: i)
                        if !player.isPlaying { player.play() }
                    },
                    onEdit: {
                        draft = $0
                        model.isDirty = true
                    },
                    // A blur while the editor is still open is a save. `save()` itself
                    // takes the editor out of edit mode, which ends editing a second time,
                    // so the state it has already left is what guards against the loop.
                    onBlur: { if editing, model.isDirty { save() } },
                    onUserScroll: { follow = false }
                )
                .frame(maxWidth: Size.readerFrame)
            }
            Spacer(minLength: .zero)
        }
        .navigationTitle(document.title)
        .toolbar {
            ToolbarItemGroup(placement: .primaryAction) {
                // One glyph at the weight of its neighbours. The pair of symbols it
                // replaces drew a tiny A beside a large one, which read as a dimmed
                // button next to a live one. The sizes are the menu's, with the two
                // steps the View menu also carries.
                Menu {
                    Picker("Text size", selection: $sizeIndex) {
                        ForEach(Type.readerSizes.indices, id: \.self) { i in
                            Text(ReaderSize.name(i)).tag(i)
                        }
                    }
                    .pickerStyle(.inline)
                    Divider()
                    Button("Smaller") { sizeIndex = ReaderSize.smaller(sizeIndex) }
                        .keyboardShortcut("-", modifiers: .command)
                        .disabled(stepIndex == 0)
                    Button("Larger") { sizeIndex = ReaderSize.larger(sizeIndex) }
                        .keyboardShortcut("=", modifiers: .command)
                        .disabled(stepIndex == ReaderSize.last)
                } label: {
                    Image(systemName: "textformat.size")
                }
                .menuIndicator(.hidden)
                .accessibilityLabel("Text size")
                .help("Text size")
                // Editing shows the file as it is written, Markdown and all, and
                // writes it back verbatim. A PDF has no source to edit.
                IconButton(editing ? "checkmark" : "pencil", label: editButtonLabel) {
                    toggleEdit()
                }
                .disabled(document.type == .pdf || loadingDraft || savesInFlight > 0)
                .help(editButtonLabel)
                IconButton("bookmark", label: "Mark finished") { model.toggleFinished(document) }
            }
        }
        .onChange(of: player.isPlaying) { _, playing in if playing { follow = true } }
        .onChange(of: editing) { _, now in model.isEditing = now }
        // The Save command, which cannot reach the draft itself.
        .onChange(of: model.saveRequested) { _, _ in if editing { save() } }
        // The navigation bar's back button is the one way out that neither the
        // transport nor Escape guards, so the way out writes the draft first.
        // The navigation bar's back button is the one way out that neither the
        // transport nor Escape guards, so the way out writes the draft first. The
        // view is going away, so the model finishes the write and keeps the text if
        // it fails; `isDirty` is cleared only by a save that landed.
        .onDisappear {
            if editing, model.isDirty { model.saveOnExit(draft, for: document) }
            model.isEditing = false
        }
        // Escape goes back to the library. While editing it does nothing, so it can
        // never be the gesture that silently discards a draft.
        .onExitCommand {
            guard !editing, !model.path.isEmpty else { return }
            model.path.removeLast()
        }
    }

    /// A script with nothing in it: an image-only or encrypted PDF, which is the case
    /// the spec names, and any file that is empty. A blank page reads as a page still
    /// loading, so the reader says which it is. Never while editing, where an empty
    /// draft is the thing being typed into.
    var showsEmptyBody: Bool { !editing && player.script.sentences.isEmpty }
    var emptyBodyMessage: String {
        document.type == .pdf ? "This PDF has no text to read" : "Nothing to read here"
    }

    /// Distinct per state, so the button never announces an action it will not perform.
    var editButtonLabel: String {
        if editing { return "Done editing" }
        return document.type == .pdf ? "Editing a PDF is not possible" : "Edit"
    }

    func nsRange(_ r: Range<String.Index>?) -> NSRange? {
        guard let r else { return nil }
        return NSRange(r, in: player.script.source)
    }

    func toggleEdit() {
        if editing {
            save()
            return
        }
        guard !loadingDraft else { return }
        player.pause()
        // A draft whose save failed on the way out comes back rather than the file,
        // which is older than it.
        if let pending = model.pendingDraft, pending.url == document.url {
            draft = pending.text
            model.pendingDraft = nil
            model.isDirty = true
            editing = true
            return
        }
        // The file, not the prose the player reads: a Markdown source extracted and
        // written back would come home with its formatting flattened out. Edit mode
        // only opens once the source is in hand, so a file that cannot be read
        // leaves the reader reading rather than editing an empty draft.
        loadingDraft = true
        Task {
            do {
                draft = try await model.vault.rawText(of: document)
                model.isDirty = false
                editing = true
            } catch {
                model.notice = "Could not open \(document.title) for editing: \(reason(error))"
            }
            loadingDraft = false
        }
    }

    /// A decode failure names itself, since "the file could not be opened" says
    /// nothing about a file the reader can see the app reading aloud.
    func reason(_ error: Error) -> String {
        guard let code = (error as? CocoaError)?.code,
            code == .fileReadInapplicableStringEncoding || code == .fileReadCorruptFile
        else { return error.localizedDescription }
        return "the file is not UTF-8 text"
    }

    /// The one write. The button stays in its editing state until the write lands, so
    /// a failed save leaves the draft on screen with the notice over it.
    func save() {
        savesInFlight += 1
        Task {
            let saved = await model.saveEdit(draft, to: document)
            savesInFlight -= 1
            if saved {
                editing = false
                model.isDirty = false
            }
        }
    }
}
