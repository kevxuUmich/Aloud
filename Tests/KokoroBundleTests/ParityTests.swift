import Foundation
import Testing

@testable import KokoroBundle

/// Runs only once `make kokoro-bundle` has filled `.build/kokoro-inputs` on this machine.
/// It builds the real bundle into a temporary folder and checks the four package tree
/// digests against the ones upstream's own builder recorded for the same files, which
/// is the proof that the Swift digest code and upstream's JavaScript agree byte for byte.
@Suite struct ParityTests {
    static let packageRoot = URL(fileURLWithPath: #filePath)
        .deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
    static let inputs = packageRoot.appendingPathComponent(".build/kokoro-inputs")

    @Test(.enabled(if: ParityTests.allInputsPresent()))
    func theTreeDigestsMatchUpstreams() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        let manifest = try BundleBuilder(
            inputs: Self.inputs, packages: KokoroInputs.packages, voices: KokoroInputs.voices
        ).build(into: root, provenance: KokoroInputs.provenance)
        for package in manifest.modelPackages {
            #expect(package.treeSHA256 == KokoroInputs.expectedTreeDigests[package.path], "\(package.path)")
            #expect(package.fileCount == 3, "\(package.path)")
        }
        #expect(manifest.modelPackages.map(\.bytes) == [44_459_888, 20_582_780, 67_266_115, 39_697_754])
        try? FileManager.default.removeItem(at: root)
    }

    static func allInputsPresent() -> Bool {
        let fetcher = Fetcher(inputs: inputs)
        return KokoroInputs.all.allSatisfy { (try? fetcher.isPresent($0)) == true }
    }
}
