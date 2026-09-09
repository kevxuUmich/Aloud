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
                Button(
                    model.progress.progress(for: doc.url)?.finished == true
                        ? "Mark Unfinished" : "Mark Finished"
                ) { model.toggleFinished(doc) }
                Divider()
                Button("Reveal in Finder") { model.reveal(doc) }
                Button("Move to Trash", role: .destructive) { model.trash(doc) }
            }
            .onDeleteCommand { model.trash(doc) }
    }
}
