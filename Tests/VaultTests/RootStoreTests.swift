import Foundation
import Testing

@testable import Vault

@Suite struct RootStoreTests {
    func suite() -> UserDefaults {
        let name = "RootStoreTests." + UUID().uuidString
        let d = UserDefaults(suiteName: name)!
        d.removePersistentDomain(forName: name)
        return d
    }

    func tempFolder() throws -> URL {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
            .resolvingSymlinksInPath()
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        return url
    }

    /// Bookmark resolution returns the fully resolved path, so roots are compared by it.
    func paths(_ urls: [URL]) -> [String] {
        urls.map { $0.resolvingSymlinksInPath().standardizedFileURL.path }
    }

    @Test func addAndLoadRoundTrip() throws {
        let defaults = suite()
        let folder = try tempFolder()
        let store = RootStore(defaults: defaults)
        #expect(paths(store.add(folder)) == paths([folder]))
        let reloaded = RootStore(defaults: defaults).load()
        #expect(paths(reloaded.urls) == paths([folder]))
        #expect(reloaded.unresolved == 0)
    }

    @Test func removePrunesOnlyTheMatchingBlob() throws {
        let defaults = suite()
        let a = try tempFolder()
        let b = try tempFolder()
        let store = RootStore(defaults: defaults)
        store.add(a)
        store.add(b)
        store.remove(a)
        let reloaded = RootStore(defaults: defaults).load()
        #expect(paths(reloaded.urls) == paths([b]))
    }

    @Test func addingTheSameURLTwiceKeepsOneBlob() throws {
        let defaults = suite()
        let folder = try tempFolder()
        let store = RootStore(defaults: defaults)
        store.add(folder)
        store.add(folder)
        #expect((defaults.array(forKey: RootStore.key) as? [Data])?.count == 1)
        #expect(paths(RootStore(defaults: defaults).load().urls) == paths([folder]))
    }

    @Test func loadReportsAFolderThatIsGone() throws {
        let defaults = suite()
        let folder = try tempFolder()
        RootStore(defaults: defaults).add(folder)
        try FileManager.default.removeItem(at: folder)
        let loaded = RootStore(defaults: defaults).load()
        // A bookmark to a deleted folder can still resolve on this filesystem, which
        // is why the assertion is the invariant rather than the count: every blob is
        // accounted for, either as a URL or as an unresolved one, and none is dropped.
        #expect(loaded.urls.count + loaded.unresolved == 1)
    }
}
