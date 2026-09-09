import Foundation
import Testing

@testable import Vault

/// The store is swapped for a throwaway suite so the tests never touch the real
/// preferences, and so one key's default cannot be read from another run's write.
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
            #expect(Defaults.noteFolderPath == "/tmp/notes")
            #expect(Defaults.voiceID == "com.apple.voice.test")
            #expect(Defaults.rateFactor == 1.25)
            #expect(Defaults.skipCode == false)
            #expect(Defaults.showMenuBar == false)
            #expect(Defaults.listView == true)
            // The names are the contract Settings reads back through @AppStorage.
            #expect(suite.string(forKey: "noteFolderPath") == "/tmp/notes")
            #expect(suite.string(forKey: "voiceID") == "com.apple.voice.test")
            #expect(suite.object(forKey: "rateFactor") as? Double == 1.25)
            #expect(suite.object(forKey: "skipCode") as? Bool == false)
            #expect(suite.object(forKey: "showMenuBar") as? Bool == false)
            #expect(suite.object(forKey: "listView") as? Bool == true)
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
        }
    }
}
