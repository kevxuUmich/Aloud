import AloudUI
import SwiftUI
import Vault

/// The library's cards. `roots` is non-empty only at the top level with more than one
/// vault folder, where the grid shows one card per root instead of flattening them.
struct LibraryGrid: View {
    var model: AppModel
    var state: LibraryState
    var roots: [Folder]
    var folders: [Folder]
    var documents: [Document]

    var shownFolders: [Folder] { roots.isEmpty ? folders : roots }
    var shownDocuments: [Document] { roots.isEmpty ? documents : [] }
    /// The ids in the order the grid lays them out, which is what a Shift range spans.
    var order: [String] { shownFolders.map(\.id) + shownDocuments.map(\.id) }

    var body: some View {
        LazyVGrid(
            // Top-aligned: a row is as tall as its tallest card, and a card with a
            // one-line title centred in a row beside a two-line one sat lower than it.
            columns: [GridItem(.adaptive(minimum: Size.cardWidth), spacing: Space.xl, alignment: .top)],
            alignment: .leading, spacing: Space.xxl
        ) {
            ForEach(shownFolders) { f in
                folderCard(f)
            }
            ForEach(shownDocuments) { d in
                Card(
                    title: d.title, preview: d.preview, status: model.status(for: d),
                    bookmarked: model.isBookmarked(d), selected: state.selection.contains(d.id),
                    icon: OriginIcon.image(for: d.origin)
                )
                .selectable(d.id, in: state, order: order) { model.open(d) }
                .documentMenu(model, d, in: state, among: shownDocuments)
            }
        }
        .padding(Space.xxl)
        .marquee(state)
    }

    /// A folder's card. A root's card carries the one thing a plain folder cannot be
    /// asked: drop it. The menu is on the roots alone, so a folder inside a vault has
    /// no empty right-click of its own.
    @ViewBuilder func folderCard(_ f: Folder) -> some View {
        let card = FolderCard(name: f.name, count: f.documentCount, selected: state.selection.contains(f.id))
            .selectable(f.id, in: state, order: order) { model.path.append(.folder(f.url)) }
        // The built-in notes folder is the one root that cannot be dropped.
        if roots.isEmpty || model.isBuiltIn(f.url) {
            card
        } else {
            card.contextMenu {
                Button("Detach Folder", role: .destructive) { model.removeRoot(f.url) }
            }
        }
    }
}
