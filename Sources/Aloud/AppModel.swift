import AloudUI
import AppKit
import Foundation
import KeyboardShortcuts
import Observation
import Prose
import ServiceManagement
import Speech
import UniformTypeIdentifiers
import Vault

@Observable @MainActor
final class AppModel {
    let vault: Vault
    let player: Player
    /// The picker needs the installed set, and it is the same provider the player
    /// speaks through, so a preview and a sentence never come from two synthesizers.
    let provider: any VoiceProvider
    let progress: ProgressStore
    let extraction = Extraction()
    private let rootStore = RootStore()
    private var watcher: FolderWatcher?
    /// The system's Now Playing panel and the media keys, and the pause that follows
    /// the headphones out of the jack. Both are started by `start()`.
    private var nowPlaying: NowPlaying?
    private var deviceWatcher: OutputDeviceWatcher?
    private var openGeneration = 0
    /// `start()` is called from the scene body, which runs again for a second window.
    /// Everything below it is process-wide - one Now Playing, one device listener, one
    /// terminate observer - so it must happen once however many times it is asked for.
    private var started = false
    /// The block-based observer `start()` registers. The centre holds it until it is
    /// removed by hand, so the token is kept for `deinit` to hand back.
    /// A `deinit` is nonisolated even on a `@MainActor` type and cannot read an
    /// isolated property, so the token is held outside the actor's isolation. It is
    /// also held outside observation: nothing renders it, and `@ObservationTracked`
    /// would make it a computed property, which `nonisolated(unsafe)` cannot describe.
    /// It is written once, from `start()`, behind the `started` guard, and read once,
    /// when the last reference is already gone, so there is no second thread to race.
    @ObservationIgnored private nonisolated(unsafe) var terminateObserver: (any NSObjectProtocol)?

    var roots: [URL] = []
    /// Every root whose bookmark will not resolve, which is what Settings names and
    /// offers to locate or remove. Each is addressed by its index in the store, since a
    /// migrated placeholder path names nothing.
    var unreachable: [RootStore.UnreachableRoot] = []
    /// `Defaults.noteFolderPath` mirrored as a stored property, because `noteFolder`
    /// reads it and a view that shows which folder is chosen has to be told when the
    /// choice changes; observation reaches a property, never a `UserDefaults` key.
    private var noteFolderPath: String? = Defaults.noteFolderPath
    /// `SMAppService.mainApp.status` mirrored for the same reason. It is read once at
    /// init and again after every write, so the toggle snaps back when a write fails.
    var launchAtLogin = SMAppService.mainApp.status == .enabled
    var tree: [Folder] = []
    var path: [Route] = []
    var current: Document?
    var notice: String?
    /// The search field's text. Every edit restarts the debounced search below.
    var searchQuery = "" { didSet { search() } }
    /// The ids that match, or nil when the field is empty and the grid is itself.
    var searchResults: Set<String>?
    private var searchTask: Task<Void, Never>?
    /// True while the reader's editor has focus, which is what takes the Playback
    /// menu's bare-key shortcuts out of the way of typing.
    var isEditing = false
    /// True while the editor holds text that is not on disk yet. It is what makes a
    /// blur, Cmd+S and leaving the reader each write, so no path out drops a draft.
    var isDirty = false
    /// Bumped by the Save command. The reader observes it rather than the menu
    /// reaching into the view, which has the draft and nothing else does.
    var saveRequested = 0
    /// A draft whose save failed on the way out of the reader. The view it belonged
    /// to is gone, so the model holds the text until that document is edited again.
    var pendingDraft: (url: URL, text: String)?
    /// The write in the air for each document, and what the last write that landed put
    /// there. Together they are what makes `saveEdit` one save at a time per file.
    private var saves: [String: Task<Bool, Never>] = [:]
    private var lastSavedText: [String: String] = [:]
    /// Bumped when the hotkey finds an empty clipboard, which is what the menu bar's
    /// glyph wiggles on. The window may be closed, so a notice would go unseen.
    var shakeCount = 0

    init(provider: any VoiceProvider, progress: ProgressStore = .standard()) {
        self.player = Player(provider: provider)
        self.provider = provider
        self.progress = progress
        let loaded = rootStore.load()
        self.roots = loaded.urls
        self.unreachable = loaded.unreachable
        self.vault = Vault(roots: loaded.urls)
        if loaded.unresolved > 0 {
            let n = loaded.unresolved
            // The bookmarks are kept: the volume may simply be unmounted.
            self.notice =
                n == 1
                ? "1 vault folder is no longer reachable"
                : "\(n) vault folders are no longer reachable"
        }
        // `Player.init` takes the system voice; the remembered one wins when it is
        // still installed, and when it is not the system voice is already in place.
        if let id = Defaults.voiceID, let v = provider.voices.first(where: { $0.id == id }) {
            player.voice = v
        }
        if let f = Defaults.rateFactor, let r = Rate(rawValue: f) { player.rate = r }
        player.onVoiceUnavailable = { [weak self] v in
            self?.notice = "\(v.name) is not available, using the system voice"
        }
        player.onSentence = { [weak self] i in self?.record(index: i, finished: false) }
        player.onFinished = { [weak self] in
            guard let self, self.current != nil else { return }
            self.record(index: self.player.sentenceIndex, finished: true)
        }
    }

    /// The one writer of `player.voice` after init, so the choice and what is
    /// remembered can never disagree. It takes at the next sentence.
    func pickVoice(_ v: Voice) {
        player.voice = v
        Defaults.voiceID = v.id
    }

    /// The one writer of `player.rate` after init, for the same reason.
    func setRate(_ r: Rate) {
        player.rate = r
        Defaults.rateFactor = r.factor
    }

    func start() {
        guard !started else { return }
        started = true
        nowPlaying = NowPlaying(player: player)
        // `[weak self]` belongs on the outer closure: on the inner `Task` alone, the
        // `@Sendable` closure the watcher holds still captures `self` strongly, and the
        // model owns the watcher, so the pair would never be freed.
        deviceWatcher = OutputDeviceWatcher { [weak self] in
            // CoreAudio calls this on its own queue, so the hop is the listener's job.
            Task { @MainActor in
                guard let self, self.player.isPlaying else { return }
                self.player.pause()
                self.notice = "Paused: the output device changed"
            }
        }
        installHotkey()
        Task { await refresh() }
        watch()
        Task { await restoreLast() }
        // The debounced write is the one thing that can still be in the air at quit.
        terminateObserver = NotificationCenter.default.addObserver(
            forName: NSApplication.willTerminateNotification, object: nil, queue: .main
        ) { [progress] _ in progress.flush() }
    }

    deinit {
        if let terminateObserver { NotificationCenter.default.removeObserver(terminateObserver) }
    }

    /// The hotkey: whatever text is on the clipboard becomes a note and starts playing,
    /// window or no window.
    func pasteAndPlay() {
        guard
            let text = NSPasteboard.general.string(forType: .string)?
                .trimmingCharacters(in: .whitespacesAndNewlines),
            !text.isEmpty
        else {
            shakeCount += 1
            return
        }
        pasteNote(andPlay: true)
    }

    /// Registered once, from `start()`, behind its `started` guard.
    private func installHotkey() {
        KeyboardShortcuts.onKeyUp(for: .pasteAndPlay) { [weak self] in
            MainActor.assumeIsolated { self?.pasteAndPlay() }
        }
    }

    func addRoot(_ url: URL) {
        roots = rootStore.add(url)
        Task {
            await vault.setRoots(roots); await refresh(); watch()
        }
    }

    /// Settings' Remove. The bookmark goes, its scoped access with it, and the library
    /// is rebuilt from what is left rather than filtered, so a document under two roots
    /// survives losing one of them.
    func removeRoot(_ url: URL) {
        rootStore.remove(url)
        roots.removeAll { $0.path == url.path }
        Task {
            await vault.setRoots(roots)
            await refresh()
            watch()
        }
    }

    /// Settings' Locate. The chosen folder takes the unreachable bookmark's place, so
    /// the root keeps its position and everything read under it keeps its progress.
    func locate(_ root: RootStore.UnreachableRoot) {
        let panel = NSOpenPanel()
        panel.canChooseDirectories = true
        panel.canChooseFiles = false
        panel.allowsMultipleSelection = false
        panel.message = "Where is \(URL(fileURLWithPath: root.path).lastPathComponent) now?"
        panel.prompt = "Read from this folder"
        guard panel.runModal() == .OK, let url = panel.url else { return }
        rootStore.replace(unreachableIndex: root.index, with: url)
        reloadRoots()
    }

    /// Settings' Remove on a root that will not resolve. The volume is not coming back,
    /// or the reader has decided it is not: either way the blob goes.
    func removeUnreachable(index: Int) {
        rootStore.remove(unreachableIndex: index)
        reloadRoots()
    }

    /// A read of the store is what republishes both lists at once, because removing or
    /// locating one blob renumbers every unreachable root after it.
    private func reloadRoots() {
        let loaded = rootStore.load()
        roots = loaded.urls
        unreachable = loaded.unreachable
        Task {
            await vault.setRoots(roots)
            await refresh()
            watch()
        }
    }

    /// The one writer of `Defaults.noteFolderPath`, the way `pickVoice` is the one
    /// writer of the voice.
    func setNoteFolder(_ url: URL) {
        Defaults.noteFolderPath = url.path
        noteFolderPath = url.path
    }

    /// Login items need a bundled, signed app: run from `make dev` this fails, and the
    /// failure is reported rather than swallowed, so the toggle never claims a state
    /// the system does not hold.
    func setLaunchAtLogin(_ on: Bool) {
        do {
            if on {
                try SMAppService.mainApp.register()
            } else {
                try SMAppService.mainApp.unregister()
            }
        } catch {
            notice = "Could not change Launch at login: \(error.localizedDescription)"
        }
        launchAtLogin = SMAppService.mainApp.status == .enabled
    }

    /// A setting that changes what the text is, such as skipping code blocks, has to
    /// reach the document already open. Not while it is being edited: re-extracting
    /// under the editor would throw the draft away.
    func reloadCurrent() {
        guard let doc = current, !isEditing else { return }
        Task { await reload(doc) }
    }

    func pickRootFolder() {
        let panel = NSOpenPanel()
        panel.canChooseDirectories = true
        panel.canChooseFiles = false
        panel.allowsMultipleSelection = false
        panel.prompt = "Read from this folder"
        if panel.runModal() == .OK, let url = panel.url { addRoot(url) }
    }

    /// The folder a new note lands in: the one that was chosen in Settings while it is
    /// still under a root, and otherwise the first root.
    var noteFolder: URL? {
        if let p = noteFolderPath,
            roots.contains(where: { Paths.isInside(p, root: $0.path) })
        {
            return URL(fileURLWithPath: p)
        }
        return roots.first
    }

    var extractOptions: ExtractOptions { ExtractOptions(skipCode: Defaults.skipCode) }

    /// The sentence being read, for a surface that shows it without the script:
    /// nil between a load and its first sentence, and whenever nothing is loaded.
    var currentSentenceText: String? {
        player.script.sentences[safe: player.sentenceIndex]?.text
    }

    /// The folder the library is looking at, which is where a drop or an import lands.
    var currentFolderURL: URL? {
        if case .folder(let url)? = path.last { return url }
        return nil
    }

    func document(at url: URL) -> Document? {
        func find(_ folders: [Folder]) -> Document? {
            for f in folders {
                if let d = f.documents.first(where: { $0.url.path == url.path }) { return d }
                if let d = find(f.folders) { return d }
            }
            return nil
        }
        return find(tree)
    }

    /// Clipboard text becomes a note in the default folder and opens ready to play.
    func pasteNote(andPlay: Bool = false) {
        guard
            let text = NSPasteboard.general.string(forType: .string)?
                .trimmingCharacters(in: .whitespacesAndNewlines),
            !text.isEmpty
        else {
            notice = "The clipboard has no text"
            return
        }
        guard let folder = noteFolder else {
            notice = "Pick a folder to read from first"
            return
        }
        Task {
            do {
                let url = try await vault.makeNote(text: text, in: folder)
                await refresh()
                if let doc = document(at: url) {
                    open(doc)
                    if andPlay { player.play() }
                }
            } catch {
                notice = "Could not save the note: \(error.localizedDescription)"
            }
        }
    }

    func importFiles(_ urls: [URL], into folder: URL? = nil) {
        guard let target = folder ?? currentFolderURL ?? noteFolder else {
            notice = "Pick a folder to read from first"
            return
        }
        Task {
            let result = Importer.importFiles(urls, into: target)
            await refresh()
            // A file that could not be copied is reported alongside the ones that were,
            // rather than costing the caller the whole drop.
            if !result.failed.isEmpty {
                notice = "Imported \(result.added.count), could not import \(result.failed.count)"
            } else if result.added.isEmpty {
                notice = "Nothing to import: Aloud reads .md, .txt and .pdf"
            }
            if result.added.count == 1, let doc = document(at: result.added[0]) { open(doc) }
        }
    }

    /// Dropped folders become roots; dropped files are imported into the current folder.
    func drop(_ urls: [URL]) {
        var isDir: ObjCBool = false
        let folders = urls.filter {
            FileManager.default.fileExists(atPath: $0.path, isDirectory: &isDir) && isDir.boolValue
        }
        let files = urls.filter { !folders.contains($0) }
        folders.forEach(addRoot)
        if !files.isEmpty { importFiles(files) }
    }

    func pickFilesToImport() {
        let panel = NSOpenPanel()
        panel.canChooseFiles = true
        panel.canChooseDirectories = false
        panel.allowsMultipleSelection = true
        panel.allowedContentTypes = [.plainText, .pdf, UTType(filenameExtension: "md") ?? .plainText]
        panel.prompt = "Import"
        if panel.runModal() == .OK { importFiles(panel.urls) }
    }

    func refresh() async {
        do {
            tree = try await vault.tree()
            let names = unreadableNames(in: tree)
            if !names.isEmpty {
                notice = "Could not read: " + names.joined(separator: ", ")
            }
        } catch {
            notice = "Could not read a vault folder: \(error.localizedDescription)"
        }
        await followCurrentFile()
    }

    /// The document being read changed on disk - saved in another editor, rewritten by
    /// a script - so the reader follows it, re-anchored on the sentence it was reading.
    /// Not while it is being edited: the draft in the editor is the newer text, and
    /// re-extracting under it would throw that away.
    private func followCurrentFile() async {
        guard let c = current, !isEditing, let fresh = document(at: c.url),
            fresh.modified != c.modified
        else { return }
        let anchorText = currentSentenceText
        current = fresh
        await reload(fresh, anchorText: anchorText)
    }

    /// Opening the document that is already loaded is navigation, not a load: it must
    /// not re-extract, and above all must not reload the player, which would throw
    /// away where the reader is.
    func open(_ doc: Document) {
        if doc.id == current?.id {
            if path.last != .reader(doc) { path.append(.reader(doc)) }
            // Reopening after the file changed underneath: the route alone would show
            // the reader the text it had when they left it. `followCurrentFile` is the
            // one place that decides, and it decides on the tree's copy rather than on
            // whatever `doc` a card was holding.
            Task { await followCurrentFile() }
            return
        }
        openGeneration += 1
        let generation = openGeneration
        Task {
            do {
                let kind = SourceKind(doc.type)
                let script = try await extraction.script(
                    for: doc.url, kind: kind, options: extractOptions)
                guard generation == openGeneration else { return }
                let p = progress.progress(for: doc.url)
                current = doc
                player.load(script, at: p?.finished == true ? 0 : (p?.sentenceIndex ?? 0))
                nowPlaying?.update(title: doc.title)
                if path.last != .reader(doc) { path.append(.reader(doc)) }
            } catch {
                guard generation == openGeneration else { return }
                notice = "Could not read \(doc.title): \(error.localizedDescription)"
            }
        }
    }

    /// The file changed under the document being read: a save, a setting that changes
    /// what the text is, or the folder watcher seeing it change on disk. It is not
    /// navigation and must never be mistaken for it, so it leaves `openGeneration` and
    /// `path` alone: bumping the generation would cancel a load the reader had already
    /// asked for, and pushing a route would send a reader who has just left the
    /// document straight back into it. The sentence is anchored rather than restored
    /// from progress, because the reader is standing in this document right now and
    /// the store is only debounced.
    ///
    /// `anchorText` is the sentence that was being read when the file changed. Given
    /// one, its place is found again in the fresh script rather than trusted: an insert
    /// above the reader moves every sentence below it, and the old number would land on
    /// the wrong line. Without one - a setting change, which rewrites the same source -
    /// the index already names the same place.
    ///
    /// A load stops the synthesizer, so playback is taken and handed back around it;
    /// otherwise a file changed mid-sentence would leave the reader silent with no
    /// press to explain it.
    func reload(_ doc: Document, anchorText: String? = nil) async {
        guard current?.id == doc.id else { return }
        let anchor = player.sentenceIndex
        do {
            let script = try await extraction.script(
                for: doc.url, kind: SourceKind(doc.type), options: extractOptions)
            // The reader may have opened something else while this was extracting.
            guard current?.id == doc.id else { return }
            let at = anchorText.map { ScriptAnchor.index(of: $0, near: anchor, in: script) } ?? anchor
            let wasPlaying = player.isPlaying
            player.load(script, at: at)
            nowPlaying?.update(title: doc.title)
            if wasPlaying { player.play() }
        } catch {
            notice = "Could not read \(doc.title): \(error.localizedDescription)"
        }
    }

    private func search() {
        searchTask?.cancel()
        let q = searchQuery
        guard !q.trimmingCharacters(in: .whitespaces).isEmpty else {
            searchResults = nil
            return
        }
        let docs = allDocuments(in: tree)
        searchTask = Task {
            try? await Task.sleep(for: .milliseconds(Int(Motion.searchDebounceMS)))
            guard !Task.isCancelled else { return }
            let hits = await Search.matches(q, in: docs)
            guard !Task.isCancelled else { return }
            searchResults = hits
        }
    }

    func allDocuments(in folders: [Folder]) -> [Document] {
        folders.flatMap { $0.documents + allDocuments(in: $0.folders) }
    }

    /// The file goes to the Trash and the library rescans; a document being read is
    /// paused first, so the player is not left talking about a file that is gone.
    func trash(_ doc: Document) {
        do {
            _ = try Trash.move(doc)
            if current?.id == doc.id { player.pause() }
            Task { await refresh() }
        } catch {
            notice = "Could not move \(doc.title) to the Trash: \(error.localizedDescription)"
        }
    }

    func reveal(_ doc: Document) { NSWorkspace.shared.activateFileViewerSelecting([doc.url]) }

    func toggleFinished(_ doc: Document) {
        let p = progress.progress(for: doc.url)
        progress.set(
            PlaybackProgress(
                sentenceIndex: p?.sentenceIndex ?? 0, finished: !(p?.finished ?? false),
                lastPlayed: .now),
            for: doc.url)
    }

    /// True when the write landed. The caller keeps the reader in its editing state
    /// until it does, so a failed save never drops the draft.
    ///
    /// This is the only way text reaches the file, and it is the funnel that keeps two
    /// saves of one document from overlapping: a blur and the Done button that follows
    /// it, or a blur and the back button. A caller arriving while a write is in the air
    /// waits for it, and then writes only if its own text is not what that write put on
    /// disk - which in the blur-then-Done case it is.
    @discardableResult
    func saveEdit(_ text: String, to doc: Document) async -> Bool {
        let key = doc.url.path
        if let inFlight = saves[key] {
            let landed = await inFlight.value
            if landed, lastSavedText[key] == text { return true }
        }
        let task = Task { await write(text, to: doc) }
        saves[key] = task
        let landed = await task.value
        if saves[key] == task { saves[key] = nil }
        return landed
    }

    /// The write itself, only ever reached through `saveEdit`.
    private func write(_ text: String, to doc: Document) async -> Bool {
        do {
            try await vault.save(text: text, to: doc)
            lastSavedText[doc.url.path] = text
            await extraction.invalidate(doc.url)
            // The reload is for the document still being read. A save on the way out
            // of a reader the user has already left behind changes the file and
            // nothing else; the folder watcher picks it up when they return.
            Task { await reload(doc) }
            return true
        } catch {
            notice = "Could not save \(doc.title): \(error.localizedDescription)"
            return false
        }
    }

    /// The save the reader cannot wait for, because the view is going away. A failure
    /// here has nowhere to put the notice and no editor left to hold the text, so the
    /// draft is kept on the model until that document is opened for editing again.
    func saveOnExit(_ text: String, for doc: Document) {
        Task {
            if await saveEdit(text, to: doc) {
                isDirty = false
                pendingDraft = nil
            } else {
                pendingDraft = (doc.url, text)
                notice = "Could not save \(doc.title); your draft is kept until you reopen it"
            }
        }
    }

    func status(for doc: Document) -> String {
        DocumentStatus.label(
            progress: progress.progress(for: doc.url), isCurrent: doc.id == current?.id,
            remaining: player.remaining, previewWords: Estimate.words(in: doc.preview),
            bytes: doc.bytes, rateFactor: player.rate.factor)
    }

    private func record(index: Int, finished: Bool) {
        guard let c = current else { return }
        progress.set(PlaybackProgress(sentenceIndex: index, finished: finished, lastPlayed: .now), for: c.url)
    }

    func folder(at url: URL) -> Folder? {
        Self.find(url: url, in: tree)
    }

    private static func find(url: URL, in folders: [Folder]) -> Folder? {
        for f in folders {
            if f.url == url { return f }
            if let found = find(url: url, in: f.folders) { return found }
        }
        return nil
    }

    private func unreadableNames(in folders: [Folder]) -> [String] {
        folders.flatMap { f -> [String] in
            f.unreadable.map { $0.lastPathComponent } + unreadableNames(in: f.folders)
        }
    }

    private func watch() {
        watcher?.stop()
        guard !roots.isEmpty else { return }
        watcher = FolderWatcher(paths: roots) { [weak self] in
            Task { @MainActor in await self?.refresh() }
        }
    }

    private func restoreLast() async {
        guard let path = progress.lastPlayedPath() else { return }
        let url = URL(fileURLWithPath: path)
        guard FileManager.default.fileExists(atPath: path), let type = DocumentType(url: url)
        else { return }
        let kind = SourceKind(type)
        if let script = try? await extraction.script(for: url, kind: kind, options: extractOptions) {
            let doc = Document(
                url: url, title: Title.from(text: script.source, fallback: url.lastPathComponent),
                preview: "", modified: .now, bytes: 0, type: type)
            current = doc
            // The same rule open() uses: a finished document starts again at the top.
            let p = progress.progress(for: url)
            player.load(script, at: p?.finished == true ? 0 : (p?.sentenceIndex ?? 0))
            // The restored document never passes through `open`, so without this the
            // panel would say "Aloud" over a document the transport can already play.
            nowPlaying?.update(title: doc.title)
        }
    }
}
