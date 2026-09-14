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

/// What can go wrong after a note's write lands on disk but before it is readable as
/// the document it just became: `writeNote`'s two checks past the write itself. Each
/// spells the whole line rather than a clause, because they land on the panel's
/// failure text and the window's notice unchanged and one of them is not a failed save
/// at all: on `.notOpened` the note is on disk, and copy that opened with "Could not
/// save the note" would tell the listener the opposite of what happened.
enum NoteWriteError: LocalizedError {
    case notFound, notOpened
    var errorDescription: String? {
        switch self {
        case .notFound: "Could not save the note where Aloud can find it again"
        case .notOpened: "Saved the note, but could not open it"
        }
    }

    /// The line a failed write leaves behind, on the panel and in the window alike.
    /// Anything that is not one of the cases above is a save that did not land, so it
    /// goes under the prefix that says so.
    static func copy(for error: Error) -> String {
        if let e = error as? NoteWriteError { return e.localizedDescription }
        return "Could not save the note: \(error.localizedDescription)"
    }
}

@Observable @MainActor
final class AppModel {
    let vault: Vault
    let player: Player
    /// The picker needs the installed set, and it is the same provider the player
    /// speaks through, so a preview and a sentence never come from two synthesizers.
    let provider: any VoiceProvider
    let progress: ProgressStore
    let extraction = Extraction()
    private let rootStore: RootStore
    private var watcher: FolderWatcher?
    /// The system's Now Playing panel and the media keys, and the pause that follows
    /// the headphones out of the jack. Both are started by `start()`.
    private var nowPlaying: NowPlaying?
    private var deviceWatcher: OutputDeviceWatcher?
    private var openGeneration = 0
    /// `start()` runs from the root view's `.task`, which runs again every time that
    /// view appears: closing the one window and reopening it from the menu bar is
    /// enough. Everything below it is process-wide - one Now Playing, one device
    /// listener, one terminate observer - so it must happen once however many times it
    /// is asked for.
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

    /// The folders the reader attached. The built-in notes folder is not among them:
    /// it is `notesFolder`, and `allRoots` is what the vault and the watcher walk.
    var roots: [URL] = []
    /// Aloud's own notes folder, made at init, or nil where it could not be made. The
    /// home of a new note when none is chosen, and a root the library always shows.
    let notesFolder: URL?
    /// Every root the library walks: the built-in folder first, then the attached
    /// ones, with the built-in path never counted twice should it also be attached.
    var allRoots: [URL] {
        guard let notesFolder else { return roots }
        return [notesFolder] + roots.filter { $0.path != notesFolder.path }
    }
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
    /// Every document in the tree, flattened once per scan. The library asks whether
    /// the vault is empty and the search asks for the corpus, both on every render;
    /// walking the tree for each of them is the same answer computed many times.
    private(set) var documents: [Document] = []
    /// True once a scan has come back, however it came back. An empty tree means an
    /// empty vault after this and means "not looked yet" before it, and the library
    /// shows a different thing for each.
    private(set) var scanned = false
    var path: [Route] = []
    var current: Document?
    var notice: String?
    /// The document a Rename… asked about. There is no dialog: the menu opens the
    /// reader and sets this, and the reader's title takes it as its cue to begin
    /// editing, then clears it.
    var renaming: Document?
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
    private var saves: [String: Save] = [:]
    private var lastSavedText: [String: String] = [:]
    /// The notice a failed `refresh` last put up. A refresh that succeeds takes its own
    /// notice down and no other: a scan that failed and then worked has nothing left to
    /// say, and a notice about a voice or a save is not this method's to clear.
    private var refreshNotice: String?
    /// The clipboard panel under the menu bar, or nil when there is none. The hotkey
    /// sets it, the panel's controller shows it, and the three methods below move it.
    var clipboardPanel: ClipboardPanelState?
    /// The write Play started, until it lands. A second Play in that time would be a
    /// second note with the same text.
    private var previewPlay: Task<Void, Never>?
    /// The note Play wrote, and the text it was written from, kept past the panel's
    /// dismissal. The hotkey with that text again, while the note is still what is
    /// loaded, brings the panel back as the note's player rather than as a preview:
    /// a preview would say the note has not started, and Play would write it again.
    private var playedNote: (id: String, preview: ClipboardPreview)?
    /// The timer that takes an empty panel down again.
    private var emptyHoldTask: Task<Void, Never>?
    /// Bumped by every mark the reader sets by hand, Finished and the bookmark. The
    /// progress store is not observable, and a card that read it alone would keep
    /// showing what it read first; reading this beside it is what makes a toggle
    /// something the library sees.
    private var marksVersion = 0
    private let emptyPanelHold: Duration
    /// What the Now Playing card says under the title for the document that is open:
    /// the folder's name, or "From clipboard" for a note the panel wrote. Kept so a
    /// reload pushes the same line, and readable so a test can check the line without
    /// a Now Playing centre to read it back from.
    private(set) var currentSubtitle: String?

    /// The root store is a parameter so a test can point it at its own defaults suite
    /// rather than at the reader's real vault.
    init(
        provider: any VoiceProvider, progress: ProgressStore = .standard(),
        rootStore: RootStore = RootStore(), notesFolder: URL = NotesFolder.url,
        emptyPanelHold: Duration = .seconds(Motion.emptyPanelHold)
    ) {
        self.emptyPanelHold = emptyPanelHold
        self.rootStore = rootStore
        self.player = Player(provider: provider)
        self.provider = provider
        self.progress = progress
        self.notesFolder = NotesFolder.ensure(notesFolder)
        let loaded = rootStore.load()
        self.roots = loaded.urls
        self.unreachable = loaded.unreachable
        var walked = loaded.urls
        if let n = self.notesFolder { walked = [n] + walked.filter { $0.path != n.path } }
        self.vault = Vault(roots: walked)
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
        if let v = Defaults.volume { player.volume = v }
        var pauses = Pauses.standard
        if let s = Defaults.sentencePause { pauses.sentence = .seconds(s) }
        if let p = Defaults.paragraphPause { pauses.paragraph = .seconds(p) }
        player.pauses = pauses
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

    /// The one writer of `player.volume` after init, likewise.
    func setVolume(_ v: Double) {
        player.volume = v
        Defaults.volume = player.volume
    }

    /// The one writer of `player.pauses` after init, likewise.
    func setPauses(_ p: Pauses) {
        player.pauses = p
        Defaults.sentencePause = p.sentence.seconds
        Defaults.paragraphPause = p.paragraph.seconds
    }

    func start() {
        guard !started else { return }
        started = true
        nowPlaying = NowPlaying(player: player, artwork: NowPlayingArtwork.make())
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

    /// The hotkey: the selection in the app in front, or failing that the clipboard,
    /// is read once and previewed, and nothing is written until the second press.
    /// Read once because a second read a moment later can hand back something else.
    ///
    /// The selection needs the Accessibility grant. Without it the first press ever
    /// asks, once, and this press and every one until it is given are the clipboard's.
    func previewSelectionOrClipboard() {
        let selection: String?
        if Selection.isTrusted {
            selection = Selection.text()
        } else {
            selection = nil
            if !Defaults.askedForSelection {
                Defaults.askedForSelection = true
                Selection.ask()
            }
        }
        preview(selection: selection, clipboard: NSPasteboard.general.string(forType: .string))
    }

    /// The clipboard alone, which is what most of the tests have.
    @discardableResult
    func preview(clipboard text: String?) -> Task<Void, Never>? {
        preview(selection: nil, clipboard: text)
    }

    /// The panel's state from text already in hand. The selection wins when there is
    /// one: it is what the listener is looking at, and the clipboard may be old.
    ///
    /// The same text as the panel already shows is the second press. A preview plays,
    /// and the task is returned so a test can wait for the write; it is one press
    /// whichever way the text arrived, selected and then copied included. Different
    /// text swaps the preview and leaves the player alone: the panel is the preview's,
    /// and the transport bar and the menu-bar item still carry the player.
    ///
    /// The text of the note the panel played, with that note still loaded, is not a
    /// new preview either, however the panel was dismissed in between: the panel
    /// comes back as the note's player, and the hotkey pauses the reading, since from
    /// another app it is the one key that reaches the player at all. It pauses the
    /// same with the panel still up: the hotkey is the stop, and Space is the toggle.
    @discardableResult
    func preview(selection: String?, clipboard: String?) -> Task<Void, Never>? {
        emptyHoldTask?.cancel()
        let new =
            selection.flatMap { ClipboardPreview(text: $0, source: .selection) }
            ?? clipboard.flatMap { ClipboardPreview(text: $0, source: .clipboard) }
        // The text the panel already shows is the second press, so the panel stays as
        // it is and the write in the air, if there is one, still belongs to it.
        if let new, clipboardPanel?.preview?.text == new.text {
            switch clipboardPanel {
            case .playing?: player.pause()
            case .preview?: return playPreview()
            default: break
            }
            return nil
        }
        // Every path past here leaves the preview a Play belonged to, the empty
        // clipboard as much as new text, so the write in the air is no longer the
        // panel's: it is cancelled here rather than left to land on a card that is gone.
        previewPlay?.cancel()
        previewPlay = nil
        if let new, let played = playedNote, played.preview.text == new.text, current?.id == played.id {
            player.pause()
            clipboardPanel = .playing(new)
            return nil
        }
        guard let p = new else {
            clipboardPanel = .empty
            emptyHoldTask = Task { [weak self, emptyPanelHold] in
                try? await Task.sleep(for: emptyPanelHold)
                guard !Task.isCancelled, let self, self.clipboardPanel == .empty else { return }
                self.clipboardPanel = nil
                self.emptyHoldTask = nil
            }
            return nil
        }
        clipboardPanel = noteFolder == nil ? .needsFolder(p) : .preview(p)
        return nil
    }

    /// The panel's Play: the note is written and opened and starts, and the panel
    /// becomes its player. Nil when there is nothing to play - no preview, no folder,
    /// or a write already in the air. The task is returned so a test can wait for it.
    @discardableResult
    func playPreview() -> Task<Void, Never>? {
        guard case .preview(let p, _)? = clipboardPanel, previewPlay == nil, let folder = noteFolder
        else { return nil }
        let task = Task {
            do {
                try await writeNote(
                    text: p.text, in: folder, andPlay: true, subtitle: p.source.label)
                // A stale task must never clear a live one: whichever of these guards
                // fires belongs to a Play that is no longer the panel's, so it returns
                // before `previewPlay = nil` below, leaving the live task's own slot alone.
                guard !Task.isCancelled, clipboardPanel?.preview == p else { return }
                // `writeNote` has checked that the note is what is loaded before it plays.
                playedNote = current.map { ($0.id, p) }
                clipboardPanel = .playing(p)
            } catch {
                guard !Task.isCancelled, clipboardPanel?.preview == p else { return }
                clipboardPanel = .preview(p, failure: NoteWriteError.copy(for: error))
            }
            previewPlay = nil
        }
        previewPlay = task
        return task
    }

    func dismissClipboardPanel() {
        emptyHoldTask?.cancel()
        clipboardPanel = nil
    }

    /// Registered once, from `start()`, behind its `started` guard.
    private func installHotkey() {
        KeyboardShortcuts.onKeyUp(for: .pasteAndPlay) { [weak self] in
            MainActor.assumeIsolated { self?.previewSelectionOrClipboard() }
        }
    }

    /// Attaching the built-in folder's own path is allowed and harmless: `allRoots`
    /// counts it once, and the bookmark only grants what the app already has.
    func addRoot(_ url: URL) {
        roots = rootStore.add(url)
        Task { await rescan() }
    }

    func isBuiltIn(_ url: URL) -> Bool { notesFolder?.path == url.path }

    /// True while new notes go to Aloud's own folder, chosen or by default.
    var usesBuiltInNotes: Bool { noteFolder.map(isBuiltIn) ?? false }

    /// Settings' Change...: any folder becomes the home of new notes, a folder inside
    /// iCloud Drive included, and is attached as a root if it is not under one already,
    /// since a note has to be in the library to be opened once it is written.
    func chooseNoteFolder() {
        let panel = NSOpenPanel()
        panel.canChooseDirectories = true
        panel.canChooseFiles = false
        panel.allowsMultipleSelection = false
        panel.prompt = "Save notes here"
        guard panel.runModal() == .OK, let url = panel.url else { return }
        if !allRoots.contains(where: { Paths.isInside(url.path, root: $0.path) }) { addRoot(url) }
        setNoteFolder(url)
    }

    /// Settings' Use Aloud's Folder: the choice is cleared, and the default is the
    /// built-in folder again.
    func useBuiltInNotes() {
        Defaults.noteFolderPath = nil
        noteFolderPath = nil
    }

    /// Settings' Detach Folder, and the library's. The bookmark goes, its scoped access with
    /// it, and the library is rebuilt from what is left rather than filtered, so a
    /// document under two roots survives losing one of them.
    ///
    /// Nothing on disk is touched, which is the whole of what the notice says: a
    /// destructive-looking menu item that only drops a link has to say that it only
    /// drops a link. What does go is the reading of a document under that root: the
    /// scoped access it was read through has just been handed back, so the player is
    /// paused and the document let go rather than left playing out of a folder the app
    /// no longer has permission to open.
    func removeRoot(_ url: URL) {
        guard !isBuiltIn(url) else { return }
        let removed = "\(url.lastPathComponent) detached from Aloud. Its files were not touched."
        // Nothing being read under this root: the order does not matter, so it stays
        // the synchronous one.
        guard let c = current, Paths.isInside(c.url.path, root: url.path) else {
            drop(url)
            notice = removed
            Task { await rescan() }
            return
        }
        // A document is being read out of the folder that is going. The reader may hold
        // an unsaved draft, and `rootStore.remove` hands back the scoped access that
        // draft would be written through, so the order here is the whole point: pause
        // and pop first, so the reader's `onDisappear` starts its save while the access
        // is still live; wait for that write; and only then drop the bookmark. Removing
        // first gave the save a folder the app was no longer allowed to open, and its
        // failure notice then replaced the removal's - the reader was told the save
        // failed and never told the folder had gone.
        player.pause()
        path.removeAll()
        Task {
            await awaitSaves(for: c.url)
            drop(url)
            current = nil
            await rescan()
            // Last, so it is the notice that stands: `refresh` posts its own when a
            // root will not read, and the thing that just happened is the removal.
            notice = removed
        }
    }

    /// The bookmark and its scoped access, gone. Split out so the two orders above
    /// cannot drift apart.
    private func drop(_ url: URL) {
        rootStore.remove(url)
        roots.removeAll { $0.path == url.path }
    }

    private func rescan() async {
        await vault.setRoots(allRoots)
        await refresh()
        watch()
    }

    /// Waits out whatever the save funnel is holding for one document, including a save
    /// that has not reached the funnel yet.
    ///
    /// `path.removeAll()` does not tear the reader down on that line: SwiftUI does it
    /// on a later pass, and the `onDisappear` that calls `saveOnExit` starts a `Task`
    /// of its own, which is where the funnel entry is finally made. So the wait is in
    /// two halves - a bounded number of main-actor turns for an entry to appear, then
    /// the entry itself - rather than one look at a dictionary that is very likely
    /// still empty.
    func awaitSaves(for url: URL) async {
        let key = url.path
        var turns = 0
        while saves[key] == nil, turns < Self.saveHandoffTurns {
            await Task.yield()
            turns += 1
        }
        while let save = saves[key] {
            _ = await save.task.value
            // A save clears the slot only while it is still the entry it made, and
            // clearing it here under the same guard is what ends this loop. A newer
            // save that has taken the slot meanwhile is waited for on the next turn.
            if saves[key] === save { saves[key] = nil }
        }
    }

    /// How many main-actor turns `awaitSaves` gives the reader's teardown to reach the
    /// funnel. Enough for a render pass and the `Task` that follows it, and small
    /// enough that a removal with no draft behind it is not a visible wait.
    private static let saveHandoffTurns = 8

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

    /// Settings' Detach Folder on a root that will not resolve. The volume is not coming back,
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
            await vault.setRoots(allRoots)
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
        // Anchored like every other reload: skipping code blocks adds and removes
        // sentences in the middle of a document, so the index the reader is standing
        // on names a different line in the script that comes back.
        let anchorText = currentSentenceText
        Task { await reload(doc, anchorText: anchorText) }
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
    /// still under a root, otherwise Aloud's own folder, and only where that could not
    /// be made, the first attached root.
    var noteFolder: URL? {
        if let p = noteFolderPath,
            allRoots.contains(where: { Paths.isInside(p, root: $0.path) })
        {
            return URL(fileURLWithPath: p)
        }
        return notesFolder ?? roots.first
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
        func find(_ folders: [Folder], _ matches: (URL) -> Bool) -> Document? {
            for f in folders {
                if let d = f.documents.first(where: { matches($0.url) }) { return d }
                if let d = find(f.folders, matches) { return d }
            }
            return nil
        }
        // The common case first, at the cost it always had: a straight `.path` compare.
        // Only on a miss is the slower fallback tried, resolving both sides - a scan's
        // own URLs come back through `FileManager`, which answers with
        // `/private/var/...` for a path a caller built as `/var/...`, and a straight
        // compare would call that a miss too.
        if let d = find(tree, { $0.path == url.path }) { return d }
        let target = url.resolvingSymlinksInPath().path
        return find(tree, { $0.resolvingSymlinksInPath().path == target })
    }

    /// Clipboard text becomes a note in the default folder and opens ready to play.
    /// The window's Cmd+Shift+V, which writes at once: it is a gesture made inside Aloud.
    func pasteNote(andPlay: Bool = false) {
        guard let p = ClipboardPreview(text: NSPasteboard.general.string(forType: .string) ?? "")
        else {
            notice = "The clipboard has no text"
            return
        }
        pasteNote(text: p.text, andPlay: andPlay)
    }

    /// The same note from text already in hand. The task is returned so a test can
    /// wait for the write and the load; nil when there is no folder to write into.
    @discardableResult
    func pasteNote(text: String, andPlay: Bool = false) -> Task<Void, Never>? {
        guard let folder = noteFolder else {
            notice = "Pick a folder to read from first"
            return nil
        }
        return Task {
            do {
                // No subtitle: the window's paste is a document like any other, and its
                // card carries the folder's name. "From clipboard" is the panel's line.
                try await writeNote(text: text, in: folder, andPlay: andPlay, subtitle: nil)
            } catch {
                notice = NoteWriteError.copy(for: error)
            }
        }
    }

    /// The write the panel and the window share. `play` waits for the load: `open`
    /// extracts in a task of its own, and a `play()` before it landed was a no-op on an
    /// empty player and, with another document loaded, a moment of the wrong one.
    ///
    /// `subtitle` is what the Now Playing card says under the title, passed straight to
    /// `open`: "From clipboard" for a note the panel wrote, and nil - the folder's name
    /// - for the window's own Cmd+Shift+V, which is a gesture made inside Aloud.
    ///
    /// A miss on either step below is thrown rather than shrugged off: a caller that
    /// swallowed it would take the success branch over a note that never opened, and
    /// the panel would show a mini player over nothing.
    private func writeNote(
        text: String, in folder: URL, andPlay: Bool, subtitle: String?
    ) async throws {
        let url = try await vault.makeNote(text: text, in: folder)
        await refresh()
        guard let doc = document(at: url) else { throw NoteWriteError.notFound }
        await open(doc, subtitle: subtitle).value
        if andPlay {
            guard current?.id == doc.id else { throw NoteWriteError.notOpened }
            player.play()
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

    /// `afterOwnSave` is set by the write below and by nothing else. It is what lets
    /// the follow run under the editor: the draft there is the text that was just
    /// written, so re-extracting cannot lose it. Every other caller leaves it alone.
    func refresh(afterOwnSave: Bool = false) async {
        var failure: String?
        do {
            tree = try await vault.tree()
            let names = unreadableNames(in: tree)
            if !names.isEmpty {
                failure = "Could not read: " + names.joined(separator: ", ")
            }
        } catch {
            failure = "Could not read a vault folder: \(error.localizedDescription)"
        }
        // A folder that was unplugged and is back, or a file that was locked and is
        // not: the notice this method put up is this method's to take down, and it is
        // taken down only while it is still the one on screen.
        if let failure {
            notice = failure
        } else if let last = refreshNotice, notice == last {
            notice = nil
        }
        refreshNotice = failure
        // A scan that failed is still a scan: the library has an answer to show, even
        // when the answer is a notice, and the first-scan spinner has to give way to it.
        scanned = true
        documents = allDocuments(in: tree)
        await followCurrentFile(evenWhileEditing: afterOwnSave)
        nameTheOpenFolder()
    }

    /// The document restored at launch is loaded before the first scan lands, so
    /// `folderName` had nothing to read and the card stood at the title alone for the
    /// rest of the session: nothing else pushes it again. The first scan that can name
    /// the folder pushes it, and only that one - a subtitle already set is left alone,
    /// so a note the panel wrote keeps "From clipboard".
    private func nameTheOpenFolder() {
        guard let doc = current, currentSubtitle == nil, let folder = folderName(of: doc) else {
            return
        }
        currentSubtitle = folder
        nowPlaying?.update(title: doc.title, subtitle: folder)
    }

    /// The document being read changed on disk - saved in another editor, rewritten by
    /// a script - so the reader follows it, re-anchored on the sentence it was reading.
    /// Not while it is being edited: the draft in the editor is the newer text, and
    /// re-extracting under it would throw that away.
    private func followCurrentFile(evenWhileEditing: Bool = false) async {
        guard let c = current, evenWhileEditing || !isEditing, let fresh = document(at: c.url),
            fresh.modified != c.modified
        else { return }
        let anchorText = currentSentenceText
        current = fresh
        await reload(fresh, anchorText: anchorText)
    }

    /// Opening the document that is already loaded is navigation, not a load: it must
    /// not re-extract, and above all must not reload the player, which would throw
    /// away where the reader is.
    ///
    /// `subtitle` is what the Now Playing card says under the title; nil means the
    /// folder the document is in. The task is returned so a caller that needs the load
    /// to have landed, such as a paste that plays, can wait for it.
    @discardableResult
    func open(_ doc: Document, subtitle: String? = nil) -> Task<Void, Never> {
        if doc.id == current?.id {
            if path.last != .reader(doc) { path.append(.reader(doc)) }
            // Reopening after the file changed underneath: the route alone would show
            // the reader the text it had when they left it. `followCurrentFile` is the
            // one place that decides, and it decides on the tree's copy rather than on
            // whatever `doc` a card was holding.
            return Task { await followCurrentFile() }
        }
        openGeneration += 1
        let generation = openGeneration
        return Task {
            do {
                let kind = SourceKind(doc.type)
                let script = try await extraction.script(
                    for: doc.url, kind: kind, options: extractOptions)
                guard generation == openGeneration else { return }
                let p = progress.progress(for: doc.url)
                current = doc
                currentSubtitle = subtitle ?? folderName(of: doc)
                player.load(script, at: p?.finished == true ? 0 : (p?.sentenceIndex ?? 0))
                nowPlaying?.update(title: doc.title, subtitle: currentSubtitle)
                if path.last != .reader(doc) { path.append(.reader(doc)) }
            } catch {
                guard generation == openGeneration else { return }
                notice = "Could not read \(doc.title): \(error.localizedDescription)"
            }
        }
    }

    /// Opens a document and plays it, once it has loaded: `open` extracts in a task of
    /// its own, and a `play()` beside it spoke a moment of whatever was loaded before,
    /// which the load then stopped, so the document opened silent. Nothing plays when
    /// another open has taken its place in the meantime. The task is returned so a
    /// caller can wait for it.
    @discardableResult
    func play(_ doc: Document) -> Task<Void, Never> {
        let opening = open(doc)
        return Task {
            await opening.value
            guard current?.id == doc.id else { return }
            player.play()
        }
    }

    /// The name of the folder that holds a document, for the card's subtitle.
    ///
    /// Two passes, in the shape `document(at:)` has above. The straight `id` compare
    /// answers for every document the scan itself built, which is all of them but one:
    /// the document restored at launch is made from a path out of the progress store,
    /// and can spell the file `/var` where `FileManager` spells it `/private/var`.
    ///
    /// The fallback is folders rather than documents: the one document's folder is
    /// resolved once and matched against each folder's own URL, so the cost is a
    /// resolve per folder and not per file in the library. That matters here more than
    /// it does above, because this runs on the main actor from every `refresh` for as
    /// long as the open document has no subtitle, and for a document whose root has
    /// been detached that is the rest of the session.
    private func folderName(of doc: Document) -> String? {
        func find(_ folders: [Folder], _ matches: (Folder) -> Bool) -> String? {
            for f in folders {
                if matches(f) { return f.name }
                if let n = find(f.folders, matches) { return n }
            }
            return nil
        }
        if let n = find(tree, { $0.documents.contains { $0.id == doc.id } }) { return n }
        let parent = doc.url.deletingLastPathComponent().resolvingSymlinksInPath().path
        return find(tree, { $0.url.resolvingSymlinksInPath().path == parent })
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
    /// `anchorText` is the sentence that was being read when the file changed, and
    /// every caller has one to hand: its place is found again in the fresh script
    /// rather than trusted, because an insert above the reader moves every sentence
    /// below it and the old number would land on the wrong line. A setting change is no
    /// exception - skipping code blocks adds and removes sentences in the middle of a
    /// document as surely as an edit does. Without an anchor the index is taken as it
    /// stands, which is only right where the script cannot have moved at all.
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
            nowPlaying?.update(title: doc.title, subtitle: currentSubtitle)
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
        let docs = documents
        searchTask = Task {
            try? await Task.sleep(for: .milliseconds(Int(Motion.searchDebounceMS)))
            guard !Task.isCancelled else { return }
            let hits = await Search.matches(q, in: docs)
            guard !Task.isCancelled else { return }
            searchResults = hits
        }
    }

    private func allDocuments(in folders: [Folder]) -> [Document] {
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

    /// The X on the transport bar: the player is silenced and emptied, nothing is
    /// loaded, and the bar says so. A reader standing in the document has nothing left
    /// to stand in, so it goes back to the library. The place in the document is kept
    /// in the progress store, as it is for every document that is closed.
    func unload() {
        guard let c = current else { return }
        player.pause()
        player.load(.empty, at: 0)
        openGeneration += 1
        current = nil
        currentSubtitle = nil
        nowPlaying?.update(title: nil, subtitle: nil)
        if path.last == .reader(c) { path.removeLast() }
    }

    /// The title the library shows, changed: rewritten into the text of a note, or
    /// the filename for a PDF. The document the model holds is swapped for the
    /// renamed one, so the bar, the reader's route and the Now Playing card carry
    /// the new title without a reload from the start; the text's own reload is the
    /// tree's, as it is after any save. A PDF's progress follows the file to its new
    /// path. A name that cannot be taken is a notice, and nothing moves.
    func rename(_ doc: Document, to title: String) async {
        do {
            let renamed = try await vault.rename(doc, to: title)
            if renamed.url != doc.url { progress.move(from: doc.url, to: renamed.url) }
            if renamed.type != .pdf {
                lastSavedText[renamed.url.path] = nil
                await extraction.invalidate(renamed.url)
            }
            if current?.id == doc.id {
                current = renamed
                nowPlaying?.update(title: renamed.title, subtitle: currentSubtitle)
            }
            if let i = path.lastIndex(of: .reader(doc)) { path[i] = .reader(renamed) }
            Task { await refresh(afterOwnSave: true) }
        } catch {
            notice = "Could not rename \(doc.title): \(error.localizedDescription)"
        }
    }

    func toggleFinished(_ doc: Document) {
        let p = progress.progress(for: doc.url)
        progress.set(
            PlaybackProgress(
                sentenceIndex: p?.sentenceIndex ?? 0, finished: !(p?.finished ?? false),
                lastPlayed: .now, bookmarked: p?.bookmarked ?? false),
            for: doc.url)
        marksVersion += 1
    }

    /// The bookmark on a document, a flag of the reader's own. It is kept with the
    /// place so it survives a rename with it, and it is not the place: the reading
    /// can move on, finish and start again and the bookmark is where it was.
    func toggleBookmark(_ doc: Document) {
        let p = progress.progress(for: doc.url)
        progress.set(
            PlaybackProgress(
                sentenceIndex: p?.sentenceIndex ?? 0, finished: p?.finished ?? false,
                lastPlayed: p?.lastPlayed ?? .distantPast, bookmarked: !(p?.bookmarked ?? false)),
            for: doc.url)
        marksVersion += 1
    }

    func isBookmarked(_ doc: Document) -> Bool {
        _ = marksVersion
        return progress.progress(for: doc.url)?.bookmarked ?? false
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
        await enqueueSave(text, to: doc).value
    }

    /// The synchronous half of `saveEdit`: the place in the queue is taken here, before
    /// the first suspension, and the write waits on the one in front of it rather than
    /// on whatever is in the slot when it wakes. Waking and looking again is not the
    /// same thing: a task's waiters are not woken in the order they began to wait, so
    /// of three saves of one file the second and third could swap and the older text
    /// be the one left on disk.
    ///
    /// It is its own entry so the order can be tested: three `async let` calls of
    /// `saveEdit` are three child tasks with no promise about which runs first, so a
    /// test that used them could see the queue formed in a different order from its
    /// source and read the wrong text back. Three calls of this on the main actor form
    /// the queue in the order they are written.
    func enqueueSave(_ text: String, to doc: Document) -> Task<Bool, Never> {
        let key = doc.url.path
        let previous = saves[key]
        let save = Save()
        saves[key] = save
        save.task = Task { [weak self] in
            let landed = await previous?.task.value ?? true
            guard let self else { return false }
            defer { if self.saves[key] === save { self.saves[key] = nil } }
            // The write in front put this very text on disk - a blur and the Done click
            // that follows it - so there is nothing left to write.
            if landed, self.lastSavedText[key] == text { return true }
            return await self.write(text, to: doc)
        }
        return save.task
    }

    /// A write in the air, held by reference so the funnel can ask whether the queue's
    /// tail is still the entry it made; a `Task` has no identity to compare. The task
    /// is set a line after the box is made, because it waits on the box in front of it.
    private final class Save {
        var task: Task<Bool, Never>!
    }

    /// The write itself, only ever reached through `saveEdit`.
    private func write(_ text: String, to doc: Document) async -> Bool {
        do {
            try await vault.save(text: text, to: doc)
            lastSavedText[doc.url.path] = text
            await extraction.invalidate(doc.url)
            // One reload per save, and it is this one. Rebuilding the tree here is what
            // moves `current` on to the new `modified`, so the folder watcher's own
            // refresh a moment later compares equal and does nothing; reloading
            // directly instead would leave that comparison different and buy a second
            // load, which restarts the sentence out loud. The reload is for the
            // document still being read: a save on the way out of a reader the user
            // has already left behind changes the file and nothing else, and
            // `followCurrentFile` declines it because `current` is no longer this one.
            // It is detached for the same reason the reload it replaces was: the write
            // has landed and the editor is waiting on that, not on a tree scan.
            Task { await refresh(afterOwnSave: true) }
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
        _ = marksVersion
        return DocumentStatus.label(
            progress: progress.progress(for: doc.url), isCurrent: doc.id == current?.id,
            remaining: player.remaining, previewWords: Estimate.words(in: doc.preview),
            bytes: doc.bytes, rateFactor: player.rate.factor)
    }

    private func record(index: Int, finished: Bool) {
        guard let c = current else { return }
        let bookmarked = progress.progress(for: c.url)?.bookmarked ?? false
        progress.set(
            PlaybackProgress(
                sentenceIndex: index, finished: finished, lastPlayed: .now, bookmarked: bookmarked),
            for: c.url)
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
        guard !allRoots.isEmpty else { return }
        watcher = FolderWatcher(paths: allRoots) { [weak self] in
            Task { @MainActor in await self?.refresh() }
        }
    }

    private func restoreLast() async {
        guard let path = progress.lastPlayedPath() else { return }
        let url = URL(fileURLWithPath: path)
        guard FileManager.default.fileExists(atPath: path), let type = DocumentType(url: url)
        else { return }
        let kind = SourceKind(type)
        // The file's own date, not this moment: `followCurrentFile` decides whether the
        // document has changed by comparing this against the tree's copy, and `.now` is
        // never what the scanner reads, so the first refresh after launch reloaded the
        // restored document and started its sentence again out loud.
        let attributes = try? FileManager.default.attributesOfItem(atPath: path)
        let modified = (attributes?[.modificationDate] as? Date) ?? .distantPast
        if let script = try? await extraction.script(for: url, kind: kind, options: extractOptions) {
            let doc = Document(
                url: url, title: Title.from(text: script.source, fallback: url.lastPathComponent),
                preview: "", modified: modified, bytes: 0, type: type)
            current = doc
            // The same rule open() uses: a finished document starts again at the top.
            let p = progress.progress(for: url)
            player.load(script, at: p?.finished == true ? 0 : (p?.sentenceIndex ?? 0))
            // The restored document never passes through `open`, so without this the
            // panel would say "Aloud" over a document the transport can already play.
            // `folderName` reads `tree`, which is usually empty here: `restoreLast` runs
            // before the first scan lands, so the subtitle is nil for now and the scan
            // fills it in through `nameTheOpenFolder`.
            currentSubtitle = folderName(of: doc)
            nowPlaying?.update(title: doc.title, subtitle: currentSubtitle)
        }
    }
}
