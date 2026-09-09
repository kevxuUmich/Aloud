import AloudUI
import Prose
import Speech
import SwiftUI
import Vault

struct ReaderView: View {
    var model: AppModel
    var document: Document
    @AppStorage("readerSizeIndex") private var sizeIndex = Type.readerDefaultIndex
    @State private var follow = true
    @State private var editing = false
    @State private var draft = ""

    var player: Player { model.player }
    var isCurrent: Bool { model.current?.id == document.id }
    /// `@AppStorage` hands back whatever is in defaults, including a value written by a
    /// build with a different number of sizes, so the index is clamped in one place.
    var stepIndex: Int { min(max(sizeIndex, 0), Type.readerSizes.count - 1) }

    var body: some View {
        HStack {
            Spacer(minLength: .zero)
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
                onEdit: { draft = $0 },
                onUserScroll: { follow = false }
            )
            .frame(maxWidth: Size.readerFrame)
            Spacer(minLength: .zero)
        }
        .navigationTitle(document.title)
        .toolbar {
            ToolbarItemGroup(placement: .primaryAction) {
                IconButton("textformat.size.smaller", label: "Smaller text") {
                    sizeIndex = max(0, stepIndex - 1)
                }
                IconButton("textformat.size.larger", label: "Larger text") {
                    sizeIndex = min(Type.readerSizes.count - 1, stepIndex + 1)
                }
                // Editing writes the prose back, which for Markdown would lose the
                // formatting; raw-source editing lands in plan 2.
                IconButton(editing ? "checkmark" : "pencil", label: editButtonLabel) {
                    toggleEdit()
                }
                .disabled(document.type != .plainText)
                .help(editButtonLabel)
                IconButton("bookmark", label: "Mark finished") { model.toggleFinished(document) }
            }
        }
        .onChange(of: player.isPlaying) { _, playing in if playing { follow = true } }
        .onChange(of: editing) { _, now in model.isEditing = now }
        .onDisappear { model.isEditing = false }
        // Escape goes back to the library. While editing it does nothing, so it can
        // never be the gesture that silently discards a draft.
        .onExitCommand {
            guard !editing, !model.path.isEmpty else { return }
            model.path.removeLast()
        }
    }

    /// Distinct per state, so the button never announces an action it will not perform.
    var editButtonLabel: String {
        if editing { return "Done editing" }
        return document.type == .plainText ? "Edit" : "Editing Markdown arrives later"
    }

    func nsRange(_ r: Range<String.Index>?) -> NSRange? {
        guard let r else { return nil }
        return NSRange(r, in: player.script.source)
    }

    func toggleEdit() {
        if editing {
            // The button stays in its editing state until the write lands; a failed
            // save leaves the draft on screen with the notice over it.
            Task { if await model.saveEdit(draft, to: document) { editing = false } }
        } else {
            player.pause()
            draft = player.script.source
            editing = true
        }
    }
}

extension Array {
    subscript(safe i: Int) -> Element? { indices.contains(i) ? self[i] : nil }
}
