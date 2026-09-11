import SwiftUI
import Vault

extension View {
    /// The right-click menu every document card and row carries, plus the Delete key,
    /// stated once so the grid and the list cannot drift apart.
    func documentMenu(_ model: AppModel, _ doc: Document) -> some View {
        self
            .contextMenu {
                Button("Play") {
                    model.open(doc)
                    model.player.play()
                }
                Button(model.isBookmarked(doc) ? "Remove Bookmark" : "Bookmark") {
                    model.toggleBookmark(doc)
                }
                Button(
                    model.progress.progress(for: doc.url)?.finished == true
                        ? "Mark Unfinished" : "Mark Finished"
                ) { model.toggleFinished(doc) }
                Divider()
                // Renaming is done in the reader, on the title itself: the menu opens
                // the document and asks the title to start editing.
                Button("Rename") {
                    model.open(doc)
                    model.renaming = doc
                }
                Button("Reveal in Finder") { model.reveal(doc) }
                Button("Move to Trash", role: .destructive) { model.trash(doc) }
            }
            .onDeleteCommand { model.trash(doc) }
    }
}
