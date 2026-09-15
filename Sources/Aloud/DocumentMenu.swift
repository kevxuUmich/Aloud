import SwiftUI
import Vault

extension View {
    /// The right-click menu every document card and row carries, stated once so the
    /// grid and the list cannot drift apart. It acts on the selection when the item is
    /// in it, and on the item alone when it is not, as Finder's does; the one action
    /// that needs a single document, Rename, goes when there are several.
    func documentMenu(_ model: AppModel, _ doc: Document, in state: LibraryState, among shown: [Document])
        -> some View
    {
        contextMenu {
            let targets =
                state.selection.contains(doc.id)
                ? shown.filter { state.selection.contains($0.id) } : [doc]
            DocumentMenuItems(model: model, targets: targets)
        }
    }
}

/// The items themselves, over one document or several. The toggles read the whole
/// set: "Bookmark" until every target is bookmarked, then "Remove Bookmark", so the
/// menu never says one thing and does two.
struct DocumentMenuItems: View {
    let model: AppModel
    let targets: [Document]

    var several: Bool { targets.count > 1 }
    var allBookmarked: Bool { targets.allSatisfy(model.isBookmarked) }
    var allFinished: Bool { targets.allSatisfy { model.progress.progress(for: $0.url)?.finished == true } }

    var body: some View {
        if let first = targets.first {
            Button("Play") { model.play(first) }
            Button(allBookmarked ? "Remove Bookmark" : "Bookmark") {
                model.setBookmarked(!allBookmarked, for: targets)
            }
            Button(allFinished ? "Mark Unfinished" : "Mark Finished") {
                model.setFinished(!allFinished, for: targets)
            }
            Divider()
            // Renaming is done in the reader, on the title itself: the menu opens
            // the document and asks the title to start editing.
            if !several {
                Button("Rename") {
                    model.open(first)
                    model.renaming = first
                }
            }
            Button("Reveal in Finder") { model.reveal(targets) }
            Button(several ? "Move \(targets.count) Items to Trash" : "Move to Trash", role: .destructive) {
                model.trash(targets)
            }
        }
    }
}
