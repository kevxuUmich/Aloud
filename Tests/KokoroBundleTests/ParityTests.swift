import Foundation
import Testing

@testable import KokoroBundle

/// Runs only once `make kokoro-bundle` has filled `.build/kokoro-inputs` on this machine.
/// It builds the real bundle into a temporary folder and checks every package's tree
/// digest against its pin: for the four packages upstream's own builder recorded, the
/// pin is upstream's, which is the proof that the Swift digest code and upstream's
/// JavaScript agree byte for byte; for the nine the short buckets added, upstream
/// declares nothing at this revision, so the pin is this repository's own first build
/// and the check is a regression check rather than a parity one. Both tables are the
/// same digest code over the same kind of tree, and the build refuses either kind of
/// difference.
@Suite struct ParityTests {
    static let packageRoot = URL(fileURLWithPath: #filePath)
        .deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
    static let inputs = packageRoot.appendingPathComponent(".build/kokoro-inputs")

    @Test(.enabled(if: ParityTests.allInputsPresent()))
    func everyPackageMatchesItsPin() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        let manifest = try BundleBuilder(
            inputs: Self.inputs, packages: KokoroInputs.packages, buckets: KokoroInputs.buckets,
            voices: KokoroInputs.voices
        ).build(into: root, provenance: KokoroInputs.provenance)
        for package in manifest.modelPackages {
            #expect(package.treeSHA256 == KokoroInputs.treeDigests[package.path], "\(package.path)")
            #expect(package.fileCount == 3, "\(package.path)")
        }
        #expect(
            manifest.modelPackages.map(\.bytes) == [
                44_459_888,
                20_582_698, 20_582_780, 20_582_780, 20_582_780,
                67_265_983, 67_266_115, 67_266_115, 67_266_115,
                39_697_341, 39_697_654, 39_697_654, 39_697_754,
            ])
        try? FileManager.default.removeItem(at: root)
    }

    /// The two tables together cover the bundle exactly once each: the four upstream
    /// recorded, the nine this repository did, and no package pinned in both or neither.
    @Test func thePinsCoverEveryPackageOnce() {
        let paths = Set(KokoroInputs.packages.map { "coreml/\($0).mlpackage" })
        let upstream = Set(KokoroInputs.expectedTreeDigests.keys)
        let recorded = Set(KokoroInputs.recordedTreeDigests.keys)
        #expect(upstream.count == 4, "\(upstream.count)")
        #expect(recorded.count == 9, "\(recorded.count)")
        #expect(upstream.isDisjoint(with: recorded))
        #expect(upstream.union(recorded) == paths)
        #expect(KokoroInputs.treeDigests.count == paths.count)
        #expect(KokoroInputs.treeDigests.values.allSatisfy { $0.count == 64 })
    }

    static func allInputsPresent() -> Bool {
        let fetcher = Fetcher(inputs: inputs)
        return KokoroInputs.all.allSatisfy { (try? fetcher.isPresent($0)) == true }
    }
}
