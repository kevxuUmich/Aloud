import AloudUI
import KeyboardShortcuts
import SwiftUI
import Vault

struct LibraryView: View {
    @Bindable var model: AppModel
    var folderURL: URL?
    /// Same key as `Defaults.listView`, so Settings and the toolbar toggle agree.
    @AppStorage("listView") private var listView = false
    /// The selection, this view's own: leaving the folder leaves it behind.
    @State private var state = LibraryState()
    @Environment(\.noticeInset) private var noticeInset

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

    /// What the grid or list is showing, in its order, for the keys that act on the
    /// selection: the folders first and then the documents, as they are laid out.
    var shownFolders: [Folder] { results != nil ? [] : (showsRoots ? model.tree : folders) }
    var shownDocuments: [Document] { results ?? (showsRoots ? [] : documents) }
    var order: [String] { shownFolders.map(\.id) + shownDocuments.map(\.id) }
    var selectedDocuments: [Document] { shownDocuments.filter { state.selection.contains($0.id) } }

    /// The hotkey as it is bound now, for the landing's hint. `AloudUI` cannot see
    /// KeyboardShortcuts; the default is the one `Name.pasteAndPlay` ships with, for
    /// the case where the user has cleared the binding.
    @MainActor static var hotkeyText: String {
        KeyboardShortcuts.getShortcut(for: .pasteAndPlay)?.description ?? "Option+Space"
    }

    var body: some View {
        Group {
            // The first scan has not come back yet, and until it does neither landing
            // can be told from a library: the built-in folder is always a root, so
            // even with nothing attached there may be notes in it. The landings were
            // asked first, and a launch with notes and no attached folder opened on
            // "Point it at a folder of notes" until the scan put the notes back.
            // A scan that fails still lands, so this cannot outlast the answer.
            if isTopLevel, !model.scanned {
                FirstScan()
            } else if model.roots.isEmpty, model.documents.isEmpty {
                // Nothing attached and nothing in Aloud's own folder: the first landing.
                // The built-in folder is a root, so it is the documents that say whether
                // there is anything to show, not the roots.
                EmptyState(
                    kind: .noVault, hotkey: Self.hotkeyText, onPrimary: model.pickRootFolder,
                    onSecondary: { model.pasteNote() })
            } else if isTopLevel, model.documents.isEmpty, results == nil {
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
                    .contentMargins(.top, noticeInset, for: .scrollContent)
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
        // The keys Finder gives a selection. Delete trashes it, Enter opens it - the
        // one folder, or the first document - Escape lets it go, and Cmd+A takes all.
        .onDeleteCommand { model.trash(selectedDocuments) }
        .onExitCommand { state.selection.clear() }
        .onKeyPress(.return) { openSelection() ? .handled : .ignored }
        .onCommand(#selector(NSResponder.selectAll(_:))) { state.selection.selectAll(in: order) }
        // A document that goes while selected, deleted here or elsewhere, leaves the
        // selection with it, so Delete never reaches for a file that is gone.
        .onChange(of: order) { _, now in state.selection.prune(to: now) }
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
        } else if isTopLevel, model.tree.count == 1, let only = model.tree.first,
            !model.isBuiltIn(only.url)
        {
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
            LibraryList(model: model, state: state, roots: [], folders: [], documents: results)
        } else if listView {
            LibraryList(
                model: model, state: state, roots: showsRoots ? model.tree : [], folders: folders,
                documents: documents)
        } else {
            LibraryGrid(
                model: model, state: state, roots: showsRoots ? model.tree : [], folders: folders,
                documents: documents)
        }
    }

    /// Enter: one selected folder is entered, else the first selected document opens.
    /// False with nothing selected, so the key goes on to whatever else wants it.
    func openSelection() -> Bool {
        let folders = shownFolders.filter { state.selection.contains($0.id) }
        if let doc = selectedDocuments.first {
            model.open(doc)
        } else if folders.count == 1, let f = folders.first {
            model.path.append(.folder(f.url))
        } else {
            return false
        }
        return true
    }
}

/// The wait for the first scan. It draws nothing for the moment a small library takes
/// to read, so a quick scan does not flash a spinner on its way to the grid, and the
/// spinner only once the wait is long enough to need saying. An empty grid would read
/// as an empty vault, which this is not yet known to be.
private struct FirstScan: View {
    @State private var slow = false

    var body: some View {
        ProgressView("Scanning your folders")
            .font(Type.caption)
            .foregroundStyle(Ink.soft)
            .padding(Space.xxl)
            .opacity(slow ? 1 : 0)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .task {
                try? await Task.sleep(for: .seconds(Motion.scanSpinnerDelay))
                withAnimation(Motion.quick) { slow = true }
            }
    }
}
