import AloudUI
import SwiftUI
import Vault

struct LibraryView: View {
    var model: AppModel
    var folderURL: URL?

    var isTopLevel: Bool { folderURL == nil }
    /// Derived live from `model.tree` on every render, so a nested grid never goes stale
    /// when the watcher refreshes it. `nil` at the top level means "show all roots"; below
    /// the top level it means the folder is gone (deleted on disk since it was opened).
    var folder: Folder? { folderURL.flatMap { model.folder(at: $0) } }
    /// True once there is more than one root: the top level then shows one card per root
    /// instead of flattening every root's contents together.
    var showsRoots: Bool { isTopLevel && model.tree.count > 1 }

    var folders: [Folder] {
        if isTopLevel { return model.tree.count == 1 ? (model.tree.first?.folders ?? []) : [] }
        return folder?.folders ?? []
    }
    var documents: [Document] {
        let docs =
            isTopLevel
            ? (model.tree.count == 1 ? (model.tree.first?.documents ?? []) : []) : (folder?.documents ?? [])
        return docs.sorted { $0.modified > $1.modified }
    }
    var title: String { isTopLevel ? "Aloud" : (folder?.name ?? "Aloud") }
    var isGone: Bool { !isTopLevel && folder == nil }

    var body: some View {
        Group {
            if model.roots.isEmpty {
                EmptyState(onPickFolder: model.pickRootFolder, onPaste: { model.pasteNote() })
            } else if isGone {
                Text("This folder is gone.")
                    .font(Type.cardTitle)
                    .foregroundStyle(Ink.soft)
                    .padding(Space.xxl)
            } else {
                ScrollView {
                    LazyVGrid(
                        columns: [GridItem(.adaptive(minimum: Size.cardWidth), spacing: Space.xl)],
                        alignment: .leading, spacing: Space.xxl
                    ) {
                        if showsRoots {
                            ForEach(model.tree) { root in
                                Button {
                                    model.path.append(.folder(root.url))
                                } label: {
                                    FolderCard(name: root.name, count: root.documentCount)
                                }.buttonStyle(.plain)
                            }
                        } else {
                            ForEach(folders) { f in
                                Button {
                                    model.path.append(.folder(f.url))
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
                    }
                    .padding(Space.xxl)
                }
                // Focusable so a bare Cmd+V reaches the library rather than the system.
                // The focus effect stays on: a keyboard user who lands on the container
                // has to be able to see that the focus is there.
                .focusable()
                .onPasteCommand(of: [.plainText]) { _ in model.pasteNote() }
            }
        }
        .navigationTitle(title)
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                Menu {
                    Button("New Note from Clipboard") { model.pasteNote() }
                    Button("Import Files...") { model.pickFilesToImport() }
                    Divider()
                    Button("Add Vault Folder...") { model.pickRootFolder() }
                } label: {
                    Image(systemName: "plus")
                }
                .accessibilityLabel("Add")
                .help("Add")
            }
        }
        .dropDestination(for: URL.self) { urls, _ in
            model.drop(urls)
            return true
        }
    }
}
