import AloudUI
import Foundation
import Speech
import Testing
import Vault

@testable import Aloud

/// The three rules the model keeps that are not a view's: one write at a time per
/// file, the newest text is the one left on disk, and a reload is not navigation.
///
/// Each case gets its own vault directory, its own progress file and its own
/// `UserDefaults` suite for the root store, so no case can see the reader's real vault
/// or another case's writes. `Defaults.store` is left alone on purpose: it is a
/// process-global that `DefaultsTests` already swaps, and `.serialized` orders one
/// suite's cases rather than two suites against each other, so a second swapper here
/// would be a race between the two targets. Nothing below writes a setting; the model
/// only reads the voice, the rate and the skip-code flag at init.
@Suite @MainActor struct AppModelTests {
    /// A model that touches nothing of the reader's: no vault roots, since the root
    /// store is pointed at a throwaway suite, and no real progress file.
    /// The built-in notes folder is the case's own directory unless a case says
    /// otherwise, so a note written with no root attached lands where the case can see
    /// it, and `addRoot(dir)` on the same path is one root, not two.
    func withModel(
        emptyPanelHold: Duration = .seconds(1), notesFolder: ((URL) -> URL)? = nil,
        _ body: (AppModel, URL) async throws -> Void
    ) async throws {
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        let name = "design.aloud.tests.\(UUID().uuidString)"
        let suite = UserDefaults(suiteName: name)!
        defer {
            suite.removePersistentDomain(forName: name)
            try? FileManager.default.removeItem(at: dir)
        }
        let model = AppModel(
            provider: FakeVoiceProvider(),
            progress: ProgressStore(file: dir.appendingPathComponent("progress.json")),
            rootStore: RootStore(defaults: suite), notesFolder: notesFolder?(dir) ?? dir,
            emptyPanelHold: emptyPanelHold)
        try await body(model, dir)
    }

    /// A document the model can open and save, made without a scan: the tree is not
    /// what any of this is about, and the model here has no roots to walk.
    func document(_ text: String, named name: String, in dir: URL) throws -> Document {
        let url = dir.appendingPathComponent(name)
        try text.write(to: url, atomically: true, encoding: .utf8)
        let attributes = try FileManager.default.attributesOfItem(atPath: url.path)
        return Document(
            url: url, title: name, preview: text,
            modified: (attributes[.modificationDate] as? Date) ?? .distantPast,
            bytes: text.utf8.count, type: .markdown)
    }

    /// `open` is a task the caller cannot await, so the suite waits for its effect.
    func poll(until condition: () -> Bool) async throws {
        let deadline = ContinuousClock.now + .seconds(1)
        while ContinuousClock.now < deadline {
            if condition() { return }
            try await Task.sleep(for: .milliseconds(10))
        }
    }

    /// Overlapping saves are queued through `enqueueSave` rather than `async let`
    /// `saveEdit`s: the child tasks of an `async let` have no fixed start order, and
    /// once in a while "one" took its place in the queue after "two" and the wrong text
    /// was read back. `enqueueSave` takes the place synchronously, so three calls in a
    /// row form the queue the suite means.
    ///
    /// The blur and the Done click that follows it. The second save waits for the
    /// first and finds its own text already on disk, so the file is written once.
    @Test func aBlurAndTheDoneThatFollowsItWriteOnce() async throws {
        try await withModel { model, dir in
            let doc = try document("old", named: "note.md", in: dir)
            let blur = model.enqueueSave("new", to: doc)
            let done = model.enqueueSave("new", to: doc)
            #expect(await blur.value)
            #expect(await done.value)
            #expect(await model.vault.writes == 1)
            #expect(try String(contentsOf: doc.url, encoding: .utf8) == "new")
        }
    }

    /// Three saves of one file overlapping: they write one at a time and in the order
    /// their callers arrived, so the newest text is the one left on disk.
    @Test func theNewestOfThreeOverlappingSavesIsWhatLands() async throws {
        try await withModel { model, dir in
            let doc = try document("old", named: "note.md", in: dir)
            let first = model.enqueueSave("one", to: doc)
            let second = model.enqueueSave("two", to: doc)
            let third = model.enqueueSave("three", to: doc)
            #expect(await first.value)
            #expect(await second.value)
            #expect(await third.value)
            #expect(await model.vault.writes == 3)
            #expect(try String(contentsOf: doc.url, encoding: .utf8) == "three")
        }
    }

    /// The redundant save in a queue of three: the last two carry the same text, and
    /// the one behind finds that text already on disk when its turn comes. It is what
    /// separates a queue from a crowd - callers that only wait for the write in the air
    /// wake together, and both of these would write.
    @Test func aSaveWhoseTextIsAlreadyOnDiskWhenItsTurnComesWritesNothing() async throws {
        try await withModel { model, dir in
            let doc = try document("old", named: "note.md", in: dir)
            let first = model.enqueueSave("one", to: doc)
            let second = model.enqueueSave("two", to: doc)
            let third = model.enqueueSave("two", to: doc)
            #expect(await first.value)
            #expect(await second.value)
            #expect(await third.value)
            #expect(await model.vault.writes == 2)
            #expect(try String(contentsOf: doc.url, encoding: .utf8) == "two")
        }
    }

    /// A reload is not navigation, so it leaves the open generation alone. Bumping it
    /// would cancel the load the reader has already asked for, and the document that
    /// was opening would never arrive.
    @Test func aReloadDoesNotCancelAnOpenInFlight() async throws {
        try await withModel { model, dir in
            let a = try document("Alpha one. Alpha two.", named: "a.md", in: dir)
            let b = try document("Beta one. Beta two.", named: "b.md", in: dir)
            model.open(a)
            try await poll { model.current?.id == a.id }
            #expect(model.current?.id == a.id)
            model.open(b)
            await model.reload(a, anchorText: model.currentSentenceText)
            try await poll { model.current?.id == b.id }
            #expect(model.current?.id == b.id)
            #expect(model.player.script.source.contains("Beta"))
        }
    }

    // MARK: Unloading and renaming

    /// The X on the bar: the player falls silent and empty, nothing is loaded, and a
    /// reader standing in that document is sent back to the library.
    @Test func unloadClearsThePlayerAndLeavesTheReader() async throws {
        try await withModel { model, dir in
            let a = try document("Alpha one. Alpha two.", named: "a.md", in: dir)
            await model.open(a).value
            model.player.play()
            #expect(model.path.last == .reader(a))
            model.unload()
            #expect(model.current == nil)
            #expect(model.currentSubtitle == nil)
            #expect(!model.player.isPlaying)
            #expect(model.player.script.sentences.isEmpty)
            #expect(model.path.isEmpty)
        }
    }

    /// Play on a document's menu plays that document. The open is a task of its own,
    /// so a `play()` beside it ran before the document had loaded: it spoke a moment of
    /// whatever was loaded before, the load that followed stopped it, and the chosen
    /// document opened silent.
    @Test func playOnADocumentPlaysItOnceItHasOpened() async throws {
        try await withModel { model, dir in
            let a = try document("Alpha one. Alpha two.", named: "a.md", in: dir)
            let b = try document("Bravo one. Bravo two.", named: "b.md", in: dir)
            await model.open(a).value
            model.player.play()
            await model.play(b).value
            #expect(model.current?.id == b.id)
            #expect(model.player.isPlaying)
            let fake = try #require(model.provider as? FakeVoiceProvider)
            #expect(fake.spoken.map(\.text) == ["Alpha one.", "Bravo one."])
        }
    }

    /// Play on the document already open plays it from where the reader is.
    @Test func playOnTheOpenDocumentPlaysItWhereItIs() async throws {
        try await withModel { model, dir in
            let a = try document("Alpha one. Alpha two.", named: "a.md", in: dir)
            await model.open(a).value
            model.player.seek(to: 1)
            await model.play(a).value
            #expect(model.player.isPlaying)
            let fake = try #require(model.provider as? FakeVoiceProvider)
            #expect(fake.spoken.map(\.text) == ["Alpha two."])
        }
    }

    /// Renaming the open note rewrites its title line, and the document the model
    /// holds carries the new title without being reopened from the start.
    @Test func renamingTheOpenNoteRetitlesItInPlace() async throws {
        try await withModel { model, dir in
            model.addRoot(dir)
            let a = try document("# Old\n\nAlpha one. Alpha two.", named: "a.md", in: dir)
            await model.open(a).value
            model.player.seek(to: 1)
            await model.rename(a, to: "New")
            #expect(model.current?.title == "New")
            #expect(try String(contentsOf: a.url, encoding: .utf8) == "# New\n\nAlpha one. Alpha two.")
            try await poll { model.documents.first?.title == "New" }
            #expect(model.documents.first?.title == "New")
        }
    }

    /// A PDF's rename moves the file, so its progress and the route to it move too.
    @Test func renamingAPDFCarriesItsProgressToTheNewPath() async throws {
        try await withModel { model, dir in
            let url = dir.appendingPathComponent("old.pdf")
            try Data("%PDF".utf8).write(to: url)
            let pdf = Document(
                url: url, title: "old", preview: "", modified: .now, bytes: 4, type: .pdf)
            model.progress.set(
                PlaybackProgress(sentenceIndex: 7, finished: false, lastPlayed: .now), for: url)
            await model.rename(pdf, to: "New")
            let moved = dir.appendingPathComponent("New.pdf")
            #expect(FileManager.default.fileExists(atPath: moved.path))
            #expect(model.progress.progress(for: moved)?.sentenceIndex == 7)
            #expect(model.progress.progress(for: url) == nil)
        }
    }

    /// A name that cannot be taken is a notice, and the file is left as it was.
    @Test func aFailedRenameIsANotice() async throws {
        try await withModel { model, dir in
            let a = try document("# Old", named: "a.md", in: dir)
            await model.rename(a, to: "   ")
            #expect(model.notice != nil)
            #expect(try String(contentsOf: a.url, encoding: .utf8) == "# Old")
        }
    }

    // MARK: Bookmarks

    /// A bookmark is a flag of the reader's own, and it outlives the reading: the
    /// place moving on and the document finishing leave it where it was.
    @Test func aBookmarkSurvivesPlaybackAndFinishing() async throws {
        try await withModel { model, dir in
            let a = try document("Alpha one. Alpha two.", named: "a.md", in: dir)
            #expect(!model.isBookmarked(a))
            model.toggleBookmark(a)
            #expect(model.isBookmarked(a))
            await model.open(a).value
            model.player.play()
            model.player.seek(to: 1)
            model.toggleFinished(a)
            #expect(model.progress.progress(for: a.url)?.finished == true)
            #expect(model.isBookmarked(a))
            model.toggleBookmark(a)
            #expect(!model.isBookmarked(a))
            #expect(model.progress.progress(for: a.url)?.finished == true)
        }
    }

    /// Both toggles change what the library shows, so each is a change a view can see.
    @Test func togglesAreObservable() async throws {
        try await withModel { model, dir in
            let a = try document("Alpha one. Alpha two.", named: "a.md", in: dir)
            let seen = Counter()
            withObservationTracking {
                _ = model.status(for: a)
            } onChange: {
                seen.bump()
            }
            model.toggleFinished(a)
            try await poll { seen.count == 1 }
            #expect(seen.count == 1)
            #expect(model.status(for: a) == "Finished")
            withObservationTracking {
                _ = model.isBookmarked(a)
            } onChange: {
                seen.bump()
            }
            model.toggleBookmark(a)
            try await poll { seen.count == 2 }
            #expect(seen.count == 2)
        }
    }

    /// A count an observation's `onChange` can bump from wherever it is called.
    final class Counter: @unchecked Sendable {
        private let lock = NSLock()
        private var n = 0
        var count: Int { lock.withLock { n } }
        func bump() { lock.withLock { n += 1 } }
    }

    // MARK: The clipboard panel

    /// The hotkey with text: a preview, and nothing on disk until Play.
    @Test func theHotkeyWithTextPreviewsAndWritesNothing() async throws {
        try await withModel { (model: AppModel, dir: URL) async throws in
            model.addRoot(dir)
            model.preview(clipboard: "  # Fast year\n\nOne two three.  ")
            let p = ClipboardPreview(text: "# Fast year\n\nOne two three.")!
            #expect(model.clipboardPanel == .preview(p))
            #expect(try FileManager.default.contentsOfDirectory(atPath: dir.path).isEmpty)
        }
    }

    /// An empty clipboard: the panel reports it, then takes itself down.
    @Test func anEmptyClipboardIsReportedThenGoes() async throws {
        try await withModel(emptyPanelHold: .milliseconds(50)) { model, dir in
            model.preview(clipboard: " \n")
            #expect(model.clipboardPanel == .empty)
            try await poll { model.clipboardPanel == nil }
            #expect(model.clipboardPanel == nil)
        }
    }

    /// The empty hold only takes down the empty state: text arriving inside the hold
    /// is a preview that stays.
    @Test func textArrivingDuringTheEmptyHoldStays() async throws {
        try await withModel(emptyPanelHold: .milliseconds(50)) { model, dir in
            model.addRoot(dir)
            model.preview(clipboard: nil)
            model.preview(clipboard: "Hello there.")
            try await Task.sleep(for: .milliseconds(100))
            #expect(model.clipboardPanel == .preview(ClipboardPreview(text: "Hello there.")!))
        }
    }

    /// No folder to write into, which takes a built-in folder that cannot be made:
    /// the panel says so, and Play has nowhere to go.
    @Test func withNoFolderThePanelAsksForOne() async throws {
        try await withModel(notesFolder: { dir in
            let file = dir.appendingPathComponent("file")
            try? "x".write(to: file, atomically: true, encoding: .utf8)
            return file.appendingPathComponent("notes")
        }) { model, _ in
            #expect(model.noteFolder == nil)
            model.preview(clipboard: "Hello there.")
            #expect(model.clipboardPanel == .needsFolder(ClipboardPreview(text: "Hello there.")!))
            #expect(model.playPreview() == nil)
        }
    }

    /// Nothing attached: a note still has a home, the built-in folder, and the
    /// library sees it there as a root of its own.
    @Test func withNoRootsANoteGoesToTheBuiltInFolder() async throws {
        try await withModel(notesFolder: { $0.appendingPathComponent("Aloud Notes") }) {
            (model: AppModel, dir: URL) async throws in
            let notes = dir.appendingPathComponent("Aloud Notes")
            #expect(model.roots.isEmpty)
            #expect(model.noteFolder?.path == notes.path)
            #expect(model.isBuiltIn(notes))
            #expect(model.usesBuiltInNotes)
            model.preview(clipboard: "Hello there.")
            #expect(model.clipboardPanel == .preview(ClipboardPreview(text: "Hello there.")!))
            await model.playPreview()?.value
            #expect(try FileManager.default.contentsOfDirectory(atPath: notes.path) == ["Hello there.md"])
            #expect(model.current?.title == "Hello there.")
            #expect(model.tree.map(\.url.path) == [notes.path])
            #expect(model.currentSubtitle == "From clipboard")
        }
    }

    /// The built-in folder is never a user root, so attaching its own path is one root.
    @Test func attachingTheBuiltInFolderIsNotASecondRoot() async throws {
        try await withModel { model, dir in
            model.addRoot(dir)
            #expect(model.allRoots.map(\.path) == [dir.path])
            #expect(model.roots.map(\.path) == [dir.path])
        }
    }

    /// Play writes exactly one note, opens it, starts it, and the panel becomes a player.
    @Test func playWritesOneNoteAndPlaysIt() async throws {
        try await withModel { model, dir in
            model.addRoot(dir)
            // A title line and a blank line before the body, the way `NoteName` and
            // `Title` both read a note: by its first line, not its first sentence.
            model.preview(clipboard: "Hello there.\n\nTwo sentences.")
            let play = try #require(model.playPreview())
            await play.value
            let files = try FileManager.default.contentsOfDirectory(atPath: dir.path)
            #expect(files == ["Hello there.md"])
            #expect(model.current?.title == "Hello there.")
            #expect(model.player.isPlaying)
            #expect(
                model.clipboardPanel == .playing(ClipboardPreview(text: "Hello there.\n\nTwo sentences.")!))
        }
    }

    /// Text pasted once already is the note it became: Play plays that note, and
    /// nothing new lands on disk.
    @Test func playingTextAlreadyPastedReusesItsNote() async throws {
        try await withModel { (model: AppModel, dir: URL) async throws in
            model.addRoot(dir)
            model.preview(clipboard: "Hello there.")
            await model.playPreview()?.value
            let note = try #require(model.current)
            model.dismissClipboardPanel()
            let a = try document("Alpha one. Alpha two.", named: "a.md", in: dir)
            await model.open(a).value
            model.preview(clipboard: "Hello there.")
            #expect(model.clipboardPanel == .preview(ClipboardPreview(text: "Hello there.")!))
            await model.playPreview()?.value
            #expect(model.clipboardPanel == .playing(ClipboardPreview(text: "Hello there.")!))
            #expect(model.current?.id == note.id)
            #expect(model.player.isPlaying)
            let files = try FileManager.default.contentsOfDirectory(atPath: dir.path).sorted()
            #expect(files == ["Hello there.md", "a.md"])
        }
    }

    @Test func aSecondPlayWhileWritingIsIgnored() async throws {
        try await withModel { model, dir in
            model.addRoot(dir)
            model.preview(clipboard: "Hello there.")
            let first = try #require(model.playPreview())
            #expect(model.playPreview() == nil)
            await first.value
            #expect(try FileManager.default.contentsOfDirectory(atPath: dir.path).count == 1)
        }
    }

    /// The hotkey again with different text swaps the preview and leaves the player alone.
    @Test func newTextSwapsThePreviewWithoutStoppingThePlayer() async throws {
        try await withModel { model, dir in
            model.addRoot(dir)
            model.preview(clipboard: "Hello there.")
            await model.playPreview()?.value
            #expect(model.player.isPlaying)
            model.preview(clipboard: "Something else.")
            #expect(model.clipboardPanel == .preview(ClipboardPreview(text: "Something else.")!))
            #expect(model.player.isPlaying)
            #expect(model.current?.title == "Hello there.")
        }
    }

    /// The same text again is the second press: a preview plays, and once playing the
    /// hotkey pauses it. Once paused, the hotkey again leaves it paused: Space is the
    /// toggle, the hotkey is the stop.
    @Test func theSameTextAgainPlaysThePreviewAndThenPausesThePlayer() async throws {
        try await withModel { (model: AppModel, dir: URL) async throws in
            model.addRoot(dir)
            model.preview(clipboard: "Hello there.")
            #expect(model.clipboardPanel == .preview(ClipboardPreview(text: "Hello there.")!))
            let play = try #require(model.preview(clipboard: " Hello there.\n"))
            await play.value
            #expect(model.clipboardPanel == .playing(ClipboardPreview(text: "Hello there.")!))
            #expect(model.player.isPlaying)
            #expect(try FileManager.default.contentsOfDirectory(atPath: dir.path).count == 1)
            #expect(model.preview(clipboard: "Hello there.") == nil)
            #expect(model.clipboardPanel == .playing(ClipboardPreview(text: "Hello there.")!))
            #expect(!model.player.isPlaying)
            model.preview(clipboard: "Hello there.")
            #expect(model.clipboardPanel == .playing(ClipboardPreview(text: "Hello there.")!))
            #expect(!model.player.isPlaying)
        }
    }

    /// The second press while the write is in the air is not a second write.
    @Test func theSameTextAgainWhileWritingIsIgnored() async throws {
        try await withModel { model, dir in
            model.addRoot(dir)
            model.preview(clipboard: "Hello there.")
            let first = try #require(model.preview(clipboard: "Hello there."))
            #expect(model.preview(clipboard: "Hello there.") == nil)
            await first.value
            #expect(try FileManager.default.contentsOfDirectory(atPath: dir.path).count == 1)
        }
    }

    /// The hotkey reads the selection in the app in front before the clipboard: what
    /// is selected is what the listener is looking at, and the clipboard may be old.
    @Test func theHotkeyPrefersTheSelectionOverTheClipboard() async throws {
        try await withModel { model, dir in
            model.addRoot(dir)
            model.preview(selection: "Picked.", clipboard: "Copied.")
            #expect(model.clipboardPanel == .preview(ClipboardPreview(text: "Picked.", source: .selection)!))
            model.preview(selection: " \n", clipboard: "Copied.")
            #expect(model.clipboardPanel == .preview(ClipboardPreview(text: "Copied.", source: .clipboard)!))
            model.preview(selection: nil, clipboard: nil)
            #expect(model.clipboardPanel == .empty)
        }
    }

    /// The same text is the same preview whichever way it arrived: selected, then
    /// copied and pressed again, is the second press and plays.
    @Test func theSameTextFromEitherSourceIsTheSecondPress() async throws {
        try await withModel { model, dir in
            model.addRoot(dir)
            model.preview(selection: "Hello there.", clipboard: nil)
            let play = try #require(model.preview(selection: nil, clipboard: "Hello there."))
            await play.value
            #expect(
                model.clipboardPanel == .playing(ClipboardPreview(text: "Hello there.", source: .selection)!))
            #expect(model.currentSubtitle == "From selection")
        }
    }

    /// Dismissing before Play leaves nothing behind; after Play the note stays and so
    /// does the playback.
    @Test func dismissClearsThePanelAndNothingElse() async throws {
        try await withModel { (model: AppModel, dir: URL) async throws in
            model.addRoot(dir)
            model.preview(clipboard: "Hello there.")
            model.dismissClipboardPanel()
            #expect(model.clipboardPanel == nil)
            #expect(try FileManager.default.contentsOfDirectory(atPath: dir.path).isEmpty)
            model.preview(clipboard: "Hello there.")
            await model.playPreview()?.value
            model.dismissClipboardPanel()
            #expect(model.clipboardPanel == nil)
            #expect(model.player.isPlaying)
            #expect(try FileManager.default.contentsOfDirectory(atPath: dir.path).count == 1)
        }
    }

    /// The hotkey again with the note's own text, after the panel was dismissed: the
    /// panel comes back as the note's player and the reading pauses. Not a preview,
    /// which would say the note has not started and would write it a second time.
    @Test func theHotkeyBringsBackThePlayerAndPausesIt() async throws {
        try await withModel { (model: AppModel, dir: URL) async throws in
            model.addRoot(dir)
            model.preview(clipboard: "Hello there.")
            await model.playPreview()?.value
            model.dismissClipboardPanel()
            #expect(model.player.isPlaying)
            model.preview(clipboard: " Hello there.\n")
            #expect(model.clipboardPanel == .playing(ClipboardPreview(text: "Hello there.")!))
            #expect(!model.player.isPlaying)
            #expect(model.playPreview() == nil)
            #expect(try FileManager.default.contentsOfDirectory(atPath: dir.path).count == 1)
        }
    }

    /// The player only comes back while the note is what is loaded: with another
    /// document open, the same text is a new preview, and that document plays on.
    @Test func theNotesTextIsAPreviewAgainOnceAnotherDocumentIsOpen() async throws {
        try await withModel { model, dir in
            model.addRoot(dir)
            model.preview(clipboard: "Hello there.")
            await model.playPreview()?.value
            model.dismissClipboardPanel()
            let a = try document("Alpha one. Alpha two.", named: "a.md", in: dir)
            await model.open(a).value
            model.player.play()
            model.preview(clipboard: "Hello there.")
            #expect(model.clipboardPanel == .preview(ClipboardPreview(text: "Hello there.")!))
            #expect(model.player.isPlaying)
            #expect(model.current?.id == a.id)
        }
    }

    /// A write that fails is reported on the panel, and Play can be pressed again.
    @Test func aFailedWriteIsReportedOnThePanel() async throws {
        try await withModel { model, dir in
            model.addRoot(dir)
            // The folder can be read but not written, so the note cannot land.
            // `setNoteFolder` is not used: it writes the reader's real defaults.
            let fm = FileManager.default
            try fm.setAttributes([.posixPermissions: 0o500], ofItemAtPath: dir.path)
            defer { try? fm.setAttributes([.posixPermissions: 0o700], ofItemAtPath: dir.path) }
            model.preview(clipboard: "Hello there.")
            await model.playPreview()?.value
            guard case .preview(let p, let failure)? = model.clipboardPanel else {
                Issue.record(
                    "expected a preview with a failure, got \(String(describing: model.clipboardPanel))")
                return
            }
            #expect(p == ClipboardPreview(text: "Hello there.")!)
            #expect(failure?.hasPrefix("Could not save the note") == true)
            #expect(model.playPreview() != nil)
        }
    }

    /// The window's own paste plays the note it wrote, not the document that was
    /// loaded before it: `play` waits for the load.
    @Test func pasteNoteAndPlayPlaysTheNote() async throws {
        try await withModel { model, dir in
            model.addRoot(dir)
            let a = try document("Alpha one. Alpha two.", named: "a.md", in: dir)
            await model.open(a).value
            #expect(model.current?.id == a.id)
            await model.pasteNote(text: "Beta one.", andPlay: true)?.value
            #expect(model.current?.title == "Beta one.")
            #expect(model.player.script.source == "Beta one.")
            #expect(model.player.isPlaying)
        }
    }

    /// The Now Playing card's second line. A document out of the library says which
    /// folder it is in; a note the panel wrote says where it came from, and the
    /// window's own paste is a document like any other.
    @Test func theCardsSecondLineNamesTheFolderOrTheClipboard() async throws {
        try await withModel { model, dir in
            model.addRoot(dir)
            let a = try document("Alpha one. Alpha two.", named: "a.md", in: dir)
            // The folder's name is read off the tree, so the scan has to have landed.
            try await poll { model.document(at: a.url) != nil }
            await model.open(a).value
            #expect(model.currentSubtitle == dir.lastPathComponent)
            model.preview(clipboard: "Hello there.")
            await model.playPreview()?.value
            #expect(model.currentSubtitle == "From clipboard")
            await model.pasteNote(text: "Gamma one.", andPlay: false)?.value
            #expect(model.currentSubtitle == dir.lastPathComponent)
        }
    }

    /// A restored document is loaded before the first scan lands, so its folder has no
    /// name yet: the scan that can name it pushes the line, and nothing else would.
    @Test func theFirstScanNamesTheFolderOfAnAlreadyOpenDocument() async throws {
        try await withModel { model, dir in
            let a = try document("Alpha one. Alpha two.", named: "a.md", in: dir)
            // Opened with no roots at all, which is where `restoreLast` leaves the model.
            await model.open(a).value
            #expect(model.current?.id == a.id)
            #expect(model.currentSubtitle == nil)
            model.addRoot(dir)
            try await poll { model.currentSubtitle != nil }
            #expect(model.currentSubtitle == dir.lastPathComponent)
        }
    }

    /// The panel's copy in each state it can be in. The three are pure given a model,
    /// so they are read straight off the view rather than through a window.
    @Test func thePanelsCopyForEachState() async throws {
        try await withModel { model, _ in
            // The rate is a process-wide setting this suite does not swap, and the
            // estimate is read at it, so the player is put at 1x for this one case.
            model.player.rate = .x1
            let view = ClipboardPanelView(model: model, actions: PanelActions())
            let text = Array(repeating: "word", count: 320).joined(separator: " ")
            let p = try #require(ClipboardPreview(text: text))
            #expect(p.words == 320)
            #expect(view.subtitle(for: .preview(p)) == "From clipboard · 1x · ~2 min · 320 words")
            let picked = try #require(ClipboardPreview(text: text, source: .selection))
            #expect(view.subtitle(for: .preview(picked)) == "From selection · 1x · ~2 min · 320 words")
            model.setRate(.x2)
            #expect(view.subtitle(for: .playing(p)) == "From clipboard · 2x · ~1 min · 320 words")
            model.player.rate = .x1
            // The level is only said once it has been lowered: full is the default and
            // a 100% on every card would be noise.
            model.setVolume(0.6)
            #expect(view.subtitle(for: .preview(p)) == "From clipboard · 1x · 60% · ~2 min · 320 words")
            model.setVolume(Player.fullVolume)
            #expect(view.subtitle(for: .preview(p)) == "From clipboard · 1x · ~2 min · 320 words")
            #expect(view.title(for: .empty) == "Nothing to read")
            #expect(view.subtitle(for: .empty) == "The clipboard has no text")
            #expect(view.subtitle(for: .needsFolder(p)) == "Pick a folder in Aloud first")
            #expect(view.subtitle(for: .preview(p, failure: "x")) == "x")
            #expect(view.transport(for: .empty) == ClipboardCard.Transport.disabled)
            #expect(view.transport(for: .preview(p)) == ClipboardCard.Transport.ready)
            #expect(view.transport(for: .needsFolder(p)) == ClipboardCard.Transport.ready)
            #expect(view.transport(for: .playing(p)) == ClipboardCard.Transport.playing(isPlaying: false))
        }
    }
}

/// A preview that knows where its text came from writes that into the note, and the
/// note comes back with it: the bar's icon and the card's line are the same origin.
@Suite @MainActor struct AppModelOriginTests {
    let tests = AppModelTests()

    @Test func playWritesTheOriginAndTheNoteCarriesIt() async throws {
        try await tests.withModel { model, dir in
            model.addRoot(dir)
            let safari = Origin(
                app: "Safari", bundle: "com.apple.Safari",
                page: .init(url: URL(string: "https://example.com/a")!, title: "Example"))
            let p = ClipboardPreview(text: "Hello there.", source: .selection, origin: safari)!
            model.preview(p)
            #expect(model.clipboardPanel == .preview(p))
            let play = try #require(model.playPreview())
            await play.value
            #expect(model.clipboardPanel == .playing(p))
            #expect(model.current?.origin == safari)
            #expect(model.currentSubtitle == "From example.com")
            let url = dir.appendingPathComponent("Hello there.md")
            #expect(try String(contentsOf: url, encoding: .utf8) == safari.frontMatter + "Hello there.")
        }
    }

    @Test func aPreviewCarriesItsOriginIntoTheLine() async throws {
        try await tests.withModel { model, dir in
            model.addRoot(dir)
            let notes = Origin(app: "Notes", bundle: "com.apple.Notes")
            let safari = Origin(app: "Safari", bundle: "com.apple.Safari")
            model.preview(ClipboardPreview(text: "Picked.", source: .selection, origin: notes))
            #expect(model.clipboardPanel?.preview?.origin == notes)
            #expect(model.clipboardPanel?.preview?.label == "From Notes")
            model.preview(ClipboardPreview(text: "Copied.", source: .clipboard, origin: safari))
            #expect(model.clipboardPanel?.preview?.label == "From Safari")
        }
    }
}
