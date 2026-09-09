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
                Button {
                    model.path.append(.folder(f.url))
                } label: {
                    FolderCard(name: f.name, count: f.documentCount)
                }.buttonStyle(.plain)
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
}
