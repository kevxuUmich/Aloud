import AppKit
import Testing
import Vault

@testable import Aloud

/// The origin of a copy, from what the copy says about itself and what the watcher
/// saw. Each case has a pasteboard of its own, so the reader's real clipboard is
/// neither read nor touched.
@Suite @MainActor struct ClipboardTests {
    let safari = Origin(app: "Safari", bundle: "com.apple.Safari")
    let notes = Origin(app: "Notes", bundle: "com.apple.Notes")

    func pasteboard() -> NSPasteboard {
        let pb = NSPasteboard(name: .init("design.aloud.tests.\(UUID().uuidString)"))
        pb.clearContents()
        return pb
    }

    @Test func aBareCopyIsCreditedToTheAppInFront() {
        let pb = pasteboard()
        pb.setString("Hello", forType: .string)
        let clipboard = Clipboard(pasteboard: pb, front: { self.notes })
        #expect(clipboard.read() == .init(text: "Hello", origin: notes))
    }

    @Test func theWatcherRemembersWhoWasInFrontWhenTheCopyWasMade() {
        let pb = pasteboard()
        var front = notes
        let clipboard = Clipboard(pasteboard: pb, front: { front })
        clipboard.tick()
        pb.clearContents()
        pb.setString("Hello", forType: .string)
        clipboard.tick()
        front = safari
        #expect(clipboard.read().origin == notes)
        // A copy the watcher has not seen yet is the front app's.
        pb.clearContents()
        pb.setString("Again", forType: .string)
        #expect(clipboard.read().origin == safari)
    }

    @Test func aChromiumCopyCarriesItsPage() {
        let pb = pasteboard()
        pb.setString("Hello", forType: .string)
        pb.setString("https://www.example.com/a?b=c", forType: Clipboard.chromiumURLType)
        let clipboard = Clipboard(pasteboard: pb, front: { self.notes })
        let read = clipboard.read()
        #expect(read.origin?.page?.url.absoluteString == "https://www.example.com/a?b=c")
        #expect(read.origin?.label == "From example.com")
    }

    @Test func aSafariCopyCarriesItsPageInTheWebArchive() throws {
        let pb = pasteboard()
        pb.setString("Hello", forType: .string)
        let archive: [String: Any] = [
            "WebMainResource": [
                "WebResourceURL": "https://example.org/page", "WebResourceData": Data(),
                "WebResourceMIMEType": "text/html",
            ]
        ]
        let data = try PropertyListSerialization.data(fromPropertyList: archive, format: .binary, options: 0)
        pb.setData(data, forType: Clipboard.webArchiveType)
        let clipboard = Clipboard(pasteboard: pb, front: { self.safari })
        #expect(clipboard.read().origin?.page?.url.absoluteString == "https://example.org/page")
    }

    @Test func aFileThePageWasOpenedFromIsNotAPage() {
        let pb = pasteboard()
        pb.setString("Hello", forType: .string)
        pb.setString("file:///Users/someone/Desktop/a.html", forType: Clipboard.chromiumURLType)
        let clipboard = Clipboard(pasteboard: pb, front: { self.notes })
        #expect(clipboard.read().origin == notes)
    }

    @Test func aStampedSourceBeatsTheAppInFront() {
        let pb = pasteboard()
        pb.setString("Hello", forType: .string)
        pb.setString("com.apple.Safari", forType: Clipboard.sourceType)
        let clipboard = Clipboard(pasteboard: pb, front: { self.notes })
        #expect(clipboard.read().origin?.bundle == "com.apple.Safari")
    }

    @Test func aConcealedCopyIsNotRead() {
        let pb = pasteboard()
        pb.setString("hunter2", forType: .string)
        pb.setString("", forType: Clipboard.concealedType)
        let clipboard = Clipboard(pasteboard: pb, front: { self.notes })
        #expect(clipboard.read() == .init(text: nil, origin: nil, concealed: true))
    }

    /// What was on the clipboard when the watcher began was copied before Aloud was
    /// looking, so the first tick credits no one and the read falls to the app in front.
    @Test func theClipboardAtLaunchIsNotCreditedToTheAppInFrontThen() {
        let pb = pasteboard()
        pb.setString("Hello", forType: .string)
        var front = Origin(app: "Aloud", bundle: Clipboard.ownBundle)
        let clipboard = Clipboard(pasteboard: pb, front: { front })
        clipboard.tick()
        front = notes
        #expect(clipboard.read().origin == notes)
    }

    /// Aloud is never where text came from: its own window in front, as with the
    /// window's paste, is no origin at all.
    @Test func aloudItselfIsNoOrigin() {
        let pb = pasteboard()
        pb.setString("Hello", forType: .string)
        let aloud = Origin(app: "Aloud", bundle: Clipboard.ownBundle)
        let clipboard = Clipboard(pasteboard: pb, front: { aloud })
        #expect(clipboard.read() == .init(text: "Hello", origin: nil))
    }

    @Test func noTextIsNoText() {
        let pb = pasteboard()
        let clipboard = Clipboard(pasteboard: pb, front: { self.notes })
        #expect(clipboard.read().text == nil)
    }
}
