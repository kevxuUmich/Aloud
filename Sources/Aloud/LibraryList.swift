import AloudUI
import SwiftUI
import Vault

/// The same library as one row per item. The search results use it with no folders.
struct LibraryList: View {
    var model: AppModel
    var state: LibraryState
    var roots: [Folder]
    var folders: [Folder]
    var documents: [Document]

    var shownFolders: [Folder] { roots.isEmpty ? folders : roots }
    var shownDocuments: [Document] { roots.isEmpty ? documents : [] }
    var order: [String] { shownFolders.map(\.id) + shownDocuments.map(\.id) }

    var body: some View {
        LazyVStack(alignment: .leading, spacing: Space.none) {
            ForEach(shownFolders) { f in
                folderRow(f)
            }
            ForEach(shownDocuments) { d in
                ListRow(
                    title: d.title, status: model.status(for: d), symbol: "doc.fill",
                    bookmarked: model.isBookmarked(d), selected: state.selection.contains(d.id)
                )
                .selectable(d.id, in: state, order: order) { model.open(d) }
                .documentMenu(model, d, in: state, among: shownDocuments)
            }
        }
        .padding(Space.xxl)
        .marquee(state)
    }

    /// The same menu the grid's root cards carry, for the same reason: a root can be
    /// dropped and a folder inside a vault cannot.
    @ViewBuilder func folderRow(_ f: Folder) -> some View {
        let row = ListRow(
            title: f.name, status: folderStatus(f), symbol: "folder.fill",
            selected: state.selection.contains(f.id)
        )
        .selectable(f.id, in: state, order: order) { model.path.append(.folder(f.url)) }
        if roots.isEmpty || model.isBuiltIn(f.url) {
            row
        } else {
            row.contextMenu {
                Button("Detach Folder", role: .destructive) { model.removeRoot(f.url) }
            }
        }
    }

    /// The same words FolderCard uses, so a folder reads alike in either view.
    func folderStatus(_ f: Folder) -> String {
        FolderCard.status(count: f.documentCount)
    }
}
