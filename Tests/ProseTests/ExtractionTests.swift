import Foundation
import Testing

@testable import Prose

@Suite struct ExtractionTests {
    @Test func cachesUntilTheFileChanges() async throws {
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        let file = dir.appendingPathComponent("a.txt")
        try "first version.".write(to: file, atomically: true, encoding: .utf8)
        let ex = Extraction()
        let a = try await ex.script(for: file, kind: .plainText, options: .default)
        #expect(a.source == "first version.")
        try "second version.".write(to: file, atomically: true, encoding: .utf8)
        try FileManager.default.setAttributes(
            [.modificationDate: Date().addingTimeInterval(5)], ofItemAtPath: file.path)
        let b = try await ex.script(for: file, kind: .plainText, options: .default)
        #expect(b.source == "second version.")
        #expect(await ex.hits == 0)
        _ = try await ex.script(for: file, kind: .plainText, options: .default)
        #expect(await ex.hits == 1)
    }
}
