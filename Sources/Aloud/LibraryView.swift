import AloudUI
import SwiftUI
import Vault

struct LibraryView: View {
    var model: AppModel
    var folder: Folder?

    var folders: [Folder] { folder?.folders ?? model.tree.flatMap { $0.folders } }
    var documents: [Document] {
        (folder?.documents ?? model.tree.flatMap { $0.documents }).sorted { $0.modified > $1.modified }
    }
    var title: String { folder?.name ?? "Aloud" }

    var body: some View {
        Group {
            if model.roots.isEmpty {
                // Paste lands in plan 2; nothing to do here yet.
                EmptyState(onPickFolder: model.pickRootFolder, onPaste: {})
            } else {
                ScrollView {
                    LazyVGrid(
                        columns: [GridItem(.adaptive(minimum: Size.cardWidth), spacing: Space.xl)],
                        alignment: .leading, spacing: Space.xxl
                    ) {
                        ForEach(folders) { f in
                            Button {
                                model.path.append(.folder(f))
                            } label: {
                                FolderCard(name: f.name, count: f.documentCount)
                            }.buttonStyle(.plain)
                        }
                        ForEach(documents) { d in
                            Button {
                                model.open(d)
                            } label: {
                                Card(title: d.title, preview: d.preview, status: model.status(for: d))
                            }.buttonStyle(.plain)
                        }
                    }
                    .padding(Space.xxl)
                }
            }
        }
        .navigationTitle(title)
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                IconButton("folder.badge.plus", label: "Add vault folder", action: model.pickRootFolder)
            }
        }
    }
}
