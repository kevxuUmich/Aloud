import Foundation
import Testing

@testable import Vault

/// The store is swapped for a throwaway suite so the tests never touch the real
/// preferences, and so one key's default cannot be read from another run's write.
///
/// `Defaults.store` is a process-global, and swapping it here swaps it for everything
/// running in this process, which is why this suite is `.serialized` and why every
/// case puts the old store back on the way out. It is also why this is the only suite
/// that swaps it: `.serialized` orders one suite's cases and not two suites against
/// each other, so a second swapper anywhere in the package would read this one's
/// throwaway suite, and this one would read theirs.
@Suite(.serialized) struct DefaultsTests {
    func withSuite(_ body: (UserDefaults) throws -> Void) rethrows {
        let name = "design.aloud.tests.\(UUID().uuidString)"
        let suite = UserDefaults(suiteName: name)!
        let previous = Defaults.store
        Defaults.store = suite
        defer {
            Defaults.store = previous
            suite.removePersistentDomain(forName: name)
        }
        try body(suite)
    }

    @Test func roundTripsEveryKey() throws {
        withSuite { suite in
            Defaults.noteFolderPath = "/tmp/notes"
            Defaults.voiceID = "com.apple.voice.test"
            Defaults.rateFactor = 1.25
            Defaults.skipCode = false
            Defaults.showMenuBar = false
            Defaults.listView = true
            Defaults.sentencePause = 0.4
            Defaults.paragraphPause = 0.6
            #expect(Defaults.noteFolderPath == "/tmp/notes")
            #expect(Defaults.voiceID == "com.apple.voice.test")
            #expect(Defaults.rateFactor == 1.25)
            #expect(Defaults.skipCode == false)
            #expect(Defaults.showMenuBar == false)
            #expect(Defaults.listView == true)
            #expect(Defaults.sentencePause == 0.4)
            #expect(Defaults.paragraphPause == 0.6)
            // The names are the contract Settings reads back through @AppStorage.
            #expect(suite.string(forKey: "noteFolderPath") == "/tmp/notes")
            #expect(suite.string(forKey: "voiceID") == "com.apple.voice.test")
            #expect(suite.object(forKey: "rateFactor") as? Double == 1.25)
            #expect(suite.object(forKey: "skipCode") as? Bool == false)
            #expect(suite.object(forKey: "showMenuBar") as? Bool == false)
            #expect(suite.object(forKey: "listView") as? Bool == true)
            #expect(suite.object(forKey: "sentencePause") as? Double == 0.4)
            #expect(suite.object(forKey: "paragraphPause") as? Double == 0.6)
        }
    }

    @Test func unsetKeysReadTheirDefaults() throws {
        withSuite { _ in
            #expect(Defaults.noteFolderPath == nil)
            #expect(Defaults.voiceID == nil)
            #expect(Defaults.rateFactor == nil)
            #expect(Defaults.skipCode == true)
            #expect(Defaults.showMenuBar == true)
            #expect(Defaults.listView == false)
            // Unset reads nil, like the rate: the player's own standard is the default,
            // and it is stated once, there.
            #expect(Defaults.sentencePause == nil)
            #expect(Defaults.paragraphPause == nil)
        }
    }
}
