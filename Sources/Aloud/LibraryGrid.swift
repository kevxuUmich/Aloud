import AloudUI
import SwiftUI
import Vault

/// The library's cards. `roots` is non-empty only at the top level with more than one
/// vault folder, where the grid shows one card per root instead of flattening them.
struct LibraryGrid: View {
    var model: AppModel
    var roots: [Folder]
    var folders: [Folder]
    var documents: [Document]

    var body: some View {
        LazyVGrid(
            columns: [GridItem(.adaptive(minimum: Size.cardWidth), spacing: Space.xl)],
            alignment: .leading, spacing: Space.xxl
        ) {
            ForEach(roots.isEmpty ? folders : roots) { f in
                folderCard(f)
            }
            if roots.isEmpty {
                ForEach(documents) { d in
                    Button {
                        model.open(d)
                    } label: {
                        Card(title: d.title, preview: d.preview, status: model.status(for: d))
                    }
                    .buttonStyle(.plain)
                    .documentMenu(model, d)
                }
            }
        }
        .padding(Space.xxl)
    }

    /// A folder's card. A root's card carries the one thing a plain folder cannot be
    /// asked: drop it. The menu is on the roots alone, so a folder inside a vault has
    /// no empty right-click of its own.
    @ViewBuilder func folderCard(_ f: Folder) -> some View {
        let card = Button {
            model.path.append(.folder(f.url))
        } label: {
            FolderCard(name: f.name, count: f.documentCount)
        }.buttonStyle(.plain)
        if roots.isEmpty {
            card
        } else {
            card.contextMenu {
                Button("Detach Folder", role: .destructive) { model.removeRoot(f.url) }
            }
        }
    }
}
