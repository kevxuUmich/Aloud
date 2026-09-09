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

    var body: some View {
        HStack {
            Spacer(minLength: .zero)
            ReaderTextView(
                text: editing ? draft : player.script.source,
                fontSize: Type.readerSizes[min(max(sizeIndex, 0), Type.readerSizes.count - 1)],
                sentence: isCurrent
                    ? nsRange(player.script.sentences[safe: player.sentenceIndex]?.range) : nil,
                word: isCurrent ? nsRange(player.wordRange) : nil,
                follow: follow && player.isPlaying,
                editable: editing,
                onClick: { offset in
                    guard let i = sentenceIndex(at: offset) else { return }
                    follow = true
                    player.seek(to: i)
                    if !player.isPlaying { player.play() }
                },
                onEdit: { draft = $0 },
                onUserScroll: { follow = false }
            )
            .frame(maxWidth: Size.readerMeasure + Space.xxl * 2)
            Spacer(minLength: .zero)
        }
        .navigationTitle(document.title)
        .toolbar {
            ToolbarItemGroup(placement: .primaryAction) {
                IconButton("textformat.size.smaller", label: "Smaller text") {
                    sizeIndex = max(0, sizeIndex - 1)
                }
                IconButton("textformat.size.larger", label: "Larger text") {
                    sizeIndex = min(Type.readerSizes.count - 1, sizeIndex + 1)
                }
                // Editing writes the prose back, which for Markdown would lose the
                // formatting; raw-source editing lands in plan 2.
                IconButton(editing ? "checkmark" : "pencil", label: editing ? "Done editing" : "Edit") {
                    toggleEdit()
                }
                .disabled(document.type != .plainText)
                IconButton("bookmark", label: "Mark finished") { model.toggleFinished(document) }
            }
        }
        .onChange(of: player.isPlaying) { _, playing in if playing { follow = true } }
    }

    func nsRange(_ r: Range<String.Index>?) -> NSRange? {
        guard let r else { return nil }
        return NSRange(r, in: player.script.source)
    }

    /// Maps a text view character offset (UTF-16) to the sentence containing it.
    func sentenceIndex(at offset: Int) -> Int? {
        let src = player.script.source
        guard offset >= 0, offset < src.utf16.count,
            let idx = Range(NSRange(location: offset, length: 0), in: src)?.lowerBound
        else { return nil }
        return player.script.sentences.lastIndex { $0.range.lowerBound <= idx }
    }

    func toggleEdit() {
        if editing {
            editing = false
            model.saveEdit(draft, to: document)
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
