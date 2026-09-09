import AloudUI
import SwiftUI
import Vault

/// The same library as one row per item. The search results use it with no folders.
struct LibraryList: View {
    var model: AppModel
    var roots: [Folder]
    var folders: [Folder]
    var documents: [Document]

    var body: some View {
        LazyVStack(alignment: .leading, spacing: Space.none) {
            ForEach(roots.isEmpty ? folders : roots) { f in
                folderRow(f)
            }
            if roots.isEmpty {
                ForEach(documents) { d in
                    Button {
                        model.open(d)
                    } label: {
                        ListRow(title: d.title, status: model.status(for: d), symbol: "doc.fill")
                    }
                    .buttonStyle(.plain)
                    .documentMenu(model, d)
                }
            }
        }
        .padding(Space.xxl)
    }

    /// The same menu the grid's root cards carry, for the same reason: a root can be
    /// dropped and a folder inside a vault cannot.
    @ViewBuilder func folderRow(_ f: Folder) -> some View {
        let row = Button {
            model.path.append(.folder(f.url))
        } label: {
            ListRow(title: f.name, status: folderStatus(f), symbol: "folder.fill")
        }.buttonStyle(.plain)
        if roots.isEmpty {
            row
        } else {
            row.contextMenu {
                Button("Detach Folder", role: .destructive) { model.removeRoot(f.url) }
            }
        }
    }

    /// The same words FolderCard uses, so a folder reads alike in either view.
    func folderStatus(_ f: Folder) -> String {
        f.documentCount == 0 ? "Empty folder" : "\(f.documentCount) documents"
    }
}
