import Foundation
import KokoroBundle

// Builds the Kokoro model bundle Aloud downloads on first use.
//
//     swift run -c release kokoro-bundle [--version 1] [--inputs .build/kokoro-inputs] [--out .build/kokoro-bundle]
//
// The inputs are fetched against pinned checksums the first time and reused after. The
// output is `kokoro-<version>.aar` and a sidecar with its SHA-256, both under `--out`.

let arguments = CommandLine.arguments

func option(_ name: String, default fallback: String) -> String {
    guard let index = arguments.firstIndex(of: name), index + 1 < arguments.count else { return fallback }
    return arguments[index + 1]
}

let version = option("--version", default: "1")
let inputs = URL(fileURLWithPath: option("--inputs", default: ".build/kokoro-inputs"))
let out = URL(fileURLWithPath: option("--out", default: ".build/kokoro-bundle"))
let name = "kokoro-\(version)"

let fetcher = Fetcher(inputs: inputs)
try await fetcher.fetch(KokoroInputs.all) { print($0) }
print("inputs complete: \(KokoroInputs.all.count) files under \(inputs.path)")

let root = out.appendingPathComponent(name)
let manifest = try BundleBuilder(inputs: inputs, packages: KokoroInputs.packages, voices: KokoroInputs.voices)
    .build(into: root, provenance: KokoroInputs.provenance)
for package in manifest.modelPackages {
    let mark =
        package.treeSHA256 == KokoroInputs.expectedTreeDigests[package.path] ? "matches upstream" : "DIFFERS"
    print("\(package.path): \(package.treeSHA256) \(mark)")
}
guard manifest.modelPackages.allSatisfy({ $0.treeSHA256 == KokoroInputs.expectedTreeDigests[$0.path] }) else {
    print("a package digest differs from the one upstream recorded; not archiving")
    exit(1)
}

let archive = out.appendingPathComponent("\(name).aar")
try AppleArchiveFile.compress(directory: root, to: archive)
let sha256 = try Digest.sha256(ofFileAt: archive)
let bytes = try archive.resourceValues(forKeys: [.fileSizeKey]).fileSize ?? 0
try "\(sha256)  \(name).aar\n".write(
    to: out.appendingPathComponent("\(name).aar.sha256"), atomically: true, encoding: .utf8)
print("\(archive.path)")
print("bytes: \(bytes)")
print("sha256: \(sha256)")
