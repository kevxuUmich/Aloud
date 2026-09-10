import AloudUI
import KeyboardShortcuts
import SwiftUI
import Vault

struct LibraryView: View {
    @Bindable var model: AppModel
    var folderURL: URL?
    /// Same key as `Defaults.listView`, so Settings and the toolbar toggle agree.
    @AppStorage("listView") private var listView = false

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
    /// A search reaches the whole tree, not the folder being looked at, and returns
    /// documents alone: a folder does not have a body to match.
    var results: [Document]? {
        guard let hits = model.searchResults else { return nil }
        return model.documents
            .filter { hits.contains($0.id) }
            .sorted { $0.modified > $1.modified }
    }
    var title: String { results != nil ? "Search" : (isTopLevel ? "Aloud" : (folder?.name ?? "Aloud")) }
    var isGone: Bool { !isTopLevel && folder == nil }

    /// The hotkey as it is bound now, for the landing's hint. `AloudUI` cannot see
    /// KeyboardShortcuts; the default is the one `Name.pasteAndPlay` ships with, for
    /// the case where the user has cleared the binding.
    @MainActor static var hotkeyText: String {
        KeyboardShortcuts.getShortcut(for: .pasteAndPlay)?.description ?? "Ctrl+Option+Space"
    }

    var body: some View {
        Group {
            if model.roots.isEmpty {
                EmptyState(
                    kind: .noVault, hotkey: Self.hotkeyText, onPrimary: model.pickRootFolder,
                    onSecondary: { model.pasteNote() })
            } else if isTopLevel, !model.scanned, model.tree.isEmpty, model.notice == nil {
                // The roots are known and the first scan has not come back yet. An
                // empty grid here would read as an empty vault, which it is not.
                // It goes as soon as a scan lands, and it never covers a notice: a
                // vault whose every root failed has something to say, and a spinner
                // that outlives the answer is a spinner that never stops.
                ProgressView("Scanning your folders")
                    .font(Type.caption)
                    .foregroundStyle(Ink.soft)
                    .padding(Space.xxl)
            } else if isTopLevel, model.scanned, model.documents.isEmpty,
                results == nil
            {
                // Folders are chosen and scanned, and not one of them holds a file this
                // app can read. A grid of empty folders would say the same thing, but
                // without the two ways out of it.
                EmptyState(
                    kind: .emptyVault, hotkey: Self.hotkeyText, onPrimary: model.pickFilesToImport,
                    onSecondary: { model.pasteNote() })
            } else if isGone {
                Text("This folder is gone.")
                    .font(Type.cardTitle)
                    .foregroundStyle(Ink.soft)
                    .padding(Space.xxl)
            } else {
                ScrollView { contents }
            }
        }
        // Focusable so a bare Cmd+V reaches the library rather than the system, and on
        // the outside of the Group so it reaches the landing too: an empty vault is
        // exactly where pasting a note is the thing to do, and the paste bound to the
        // grid alone was a command that worked everywhere except where it was offered.
        // No focus effect: the window hands first responder to this container the
        // moment it opens, and SwiftUI rings a focused view whether the keyboard put
        // it there or not, so every launch began with a blue rectangle around the
        // content. The paste stays reachable without focus through the landing's
        // button and Cmd+Shift+V, and a keyboard user tabbing through lands on the
        // buttons, which draw their own rings.
        .focusable()
        .focusEffectDisabled()
        .onPasteCommand(of: [.plainText]) { _ in model.pasteNote() }
        .navigationTitle(title)
        .searchable(text: $model.searchQuery, placement: .toolbar, prompt: "Search")
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                Picker("View", selection: $listView) {
                    Image(systemName: "square.grid.2x2").accessibilityLabel("Grid").tag(false)
                    Image(systemName: "list.bullet").accessibilityLabel("List").tag(true)
                }
                .pickerStyle(.segmented)
                .help("Grid or list")
            }
            ToolbarItem(placement: .primaryAction) {
                Menu {
                    Button("New Note from Clipboard") { model.pasteNote() }
                    Button("Import Files...") { model.pickFilesToImport() }
                    Divider()
                    Button("Add Vault Folder...") { model.pickRootFolder() }
                    removeFolderItem
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

    /// Detaching the folder that is on screen. Inside a root it is that root; at the top
    /// level it is the single root whose contents are being shown flattened, which has
    /// no card of its own to right-click. Anywhere else there is no one folder the menu
    /// could mean, and the roots' own cards carry the item instead.
    @ViewBuilder var removeFolderItem: some View {
        if let url = folderURL, model.roots.contains(where: { $0.path == url.path }) {
            Divider()
            Button("Detach This Folder", role: .destructive) {
                model.removeRoot(url)
                // The folder just stopped existing as far as the library is concerned,
                // so the view showing it cannot stay on the stack.
                model.path.removeAll()
            }
        } else if isTopLevel, model.tree.count == 1, let only = model.tree.first {
            Divider()
            Button("Detach \(only.name)", role: .destructive) {
                model.removeRoot(only.url)
            }
        }
    }

    /// One of three: the flat search results, the list, or the grid. Clearing the field
    /// drops `searchResults` back to nil and the folder returns exactly as it was.
    @ViewBuilder var contents: some View {
        if let results {
            LibraryList(model: model, roots: [], folders: [], documents: results)
        } else if listView {
            LibraryList(
                model: model, roots: showsRoots ? model.tree : [], folders: folders,
                documents: documents)
        } else {
            LibraryGrid(
                model: model, roots: showsRoots ? model.tree : [], folders: folders,
                documents: documents)
        }
    }
}
