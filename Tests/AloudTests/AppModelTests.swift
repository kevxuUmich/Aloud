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
    func withModel(
        emptyPanelHold: Duration = .seconds(1),
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
            rootStore: RootStore(defaults: suite), emptyPanelHold: emptyPanelHold)
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

    /// No folder to write into: the panel says so, and Play has nowhere to go.
    @Test func withNoFolderThePanelAsksForOne() async throws {
        try await withModel { model, _ in
            model.preview(clipboard: "Hello there.")
            #expect(model.clipboardPanel == .needsFolder(ClipboardPreview(text: "Hello there.")!))
            #expect(model.playPreview() == nil)
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
            #expect(files == ["Hello there..md"] || files == ["Hello there.md"])
            #expect(model.current?.title == "Hello there.")
            #expect(model.player.isPlaying)
            #expect(
                model.clipboardPanel == .playing(ClipboardPreview(text: "Hello there.\n\nTwo sentences.")!))
        }
    }

    /// A second Play while the first is still writing is one write, not two.
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

    /// The same text again changes nothing, whether previewing or playing.
    @Test func theSameTextAgainIsANoOp() async throws {
        try await withModel { model, dir in
            model.addRoot(dir)
            model.preview(clipboard: "Hello there.")
            model.preview(clipboard: "Hello there.")
            #expect(model.clipboardPanel == .preview(ClipboardPreview(text: "Hello there.")!))
            await model.playPreview()?.value
            model.preview(clipboard: " Hello there.\n")
            #expect(model.clipboardPanel == .playing(ClipboardPreview(text: "Hello there.")!))
            #expect(model.player.isPlaying)
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
}
