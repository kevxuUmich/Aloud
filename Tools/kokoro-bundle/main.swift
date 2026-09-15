import Foundation
import KokoroBundle

// Builds the Kokoro model bundle Aloud downloads on first use.
//
//     swift run -c release kokoro-bundle --version 2 [--inputs .build/kokoro-inputs] [--out .build/kokoro-bundle]
//
// The inputs are fetched against pinned checksums the first time and reused after. The
// output is `kokoro-<version>.aar` and a sidecar with its SHA-256, both under `--out`.

let usage = """
    Usage: kokoro-bundle --version <version> [--inputs <path>] [--out <path>] [--help]

      --version   Bundle version, used in the output file names (required)
      --inputs    Folder the pinned inputs are fetched into (default: .build/kokoro-inputs)
      --out       Folder the archive and its sidecar are written into (default: .build/kokoro-bundle)
      --help      Print this message and exit
    """

let knownFlags: Set<String> = ["--version", "--inputs", "--out"]
let arguments = Array(CommandLine.arguments.dropFirst())

if arguments.contains("--help") {
    print(usage)
    exit(0)
}

var values: [String: String] = [:]
var index = 0
while index < arguments.count {
    let flag = arguments[index]
    guard knownFlags.contains(flag) else {
        FileHandle.standardError.write(Data("unrecognized argument: \(flag)\n\n\(usage)\n".utf8))
        exit(2)
    }
    guard index + 1 < arguments.count else {
        FileHandle.standardError.write(Data("\(flag) needs a value\n\n\(usage)\n".utf8))
        exit(2)
    }
    values[flag] = arguments[index + 1]
    index += 2
}

// No default. The pinned inputs are whatever this commit lists, so a bare run used to
// write a four-bucket archive under the one-bucket release's name.
guard let version = values["--version"] else {
    FileHandle.standardError.write(Data("--version is required\n\n\(usage)\n".utf8))
    exit(2)
}
let inputs = URL(fileURLWithPath: values["--inputs"] ?? ".build/kokoro-inputs")
let out = URL(fileURLWithPath: values["--out"] ?? ".build/kokoro-bundle")
let name = "kokoro-\(version)"
let archive = out.appendingPathComponent("\(name).aar")
let sidecar = out.appendingPathComponent("\(name).aar.sha256")

// A failed build must not leave a stale archive or sidecar sitting next to a fresh,
// unfinished layout: whatever this run produces, it produces from a clean slate.
try? FileManager.default.removeItem(at: archive)
try? FileManager.default.removeItem(at: sidecar)

let fetcher = Fetcher(inputs: inputs)
try await fetcher.fetch(KokoroInputs.all) { print($0) }
print("inputs complete: \(KokoroInputs.all.count) files under \(inputs.path)")

let root = out.appendingPathComponent(name)
let manifest = try BundleBuilder(
    inputs: inputs, packages: KokoroInputs.packages, buckets: KokoroInputs.buckets,
    voices: KokoroInputs.voices
).build(into: root, provenance: KokoroInputs.provenance)

// Every package is pinned, by upstream's own recorded digest where upstream has one and
// by this repository's first build where it does not; both are refused on a difference.
let pins = KokoroInputs.treeDigests
for package in manifest.modelPackages {
    let mark: String
    if package.treeSHA256 != pins[package.path] {
        mark = "DIFFERS"
    } else if KokoroInputs.expectedTreeDigests[package.path] != nil {
        mark = "matches upstream"
    } else {
        mark = "matches the recorded pin"
    }
    print("\(package.path): \(package.treeSHA256) \(mark)")
}
guard manifest.modelPackages.allSatisfy({ $0.treeSHA256 == pins[$0.path] }) else {
    print("a package digest differs from its pin; not archiving")
    exit(1)
}

try AppleArchiveFile.compress(directory: root, to: archive)

// Prove the archive is not truncated or corrupt before it is ever trusted: extract it
// back out into a scratch folder and check what came back against what was laid out.
//
// The manifest alone is not enough. It is a unique file and always carries its own data,
// while the one thing hard-link deduplication could get wrong is a cluster follower
// coming back with no data at all, which is every weight file but one. So every package
// is re-digested out of the extracted tree and compared with the digest just taken from
// the built layout, which covers every file rather than one.
let verify = out.appendingPathComponent("\(name)-verify-\(UUID().uuidString)")
func cleanUpVerify() { try? FileManager.default.removeItem(at: verify) }
do {
    try AppleArchiveFile.extract(archive: archive, into: verify)
    let extracted = try Data(contentsOf: verify.appendingPathComponent(RuntimeManifest.fileName))
    let built = try Data(contentsOf: root.appendingPathComponent(RuntimeManifest.fileName))
    guard extracted == built else {
        cleanUpVerify()
        try? FileManager.default.removeItem(at: archive)
        print("extracted manifest does not match the built layout; not publishing \(archive.path)")
        exit(1)
    }
    for package in manifest.modelPackages {
        let back = try Digest.package(
            at: verify.appendingPathComponent(package.path), path: package.path)
        guard back.treeSHA256 == package.treeSHA256, back.fileCount == package.fileCount,
            back.bytes == package.bytes
        else {
            cleanUpVerify()
            try? FileManager.default.removeItem(at: archive)
            print("\(package.path) came back from the archive different; not publishing \(archive.path)")
            exit(1)
        }
    }
    cleanUpVerify()
} catch {
    cleanUpVerify()
    try? FileManager.default.removeItem(at: archive)
    print("could not verify the archive by extraction: \(error)")
    exit(1)
}
print("archive verified by extraction: \(manifest.modelPackages.count) package digests re-checked")

let sha256 = try Digest.sha256(ofFileAt: archive)
let bytes = try archive.resourceValues(forKeys: [.fileSizeKey]).fileSize ?? 0
try "\(sha256)  \(name).aar\n".write(to: sidecar, atomically: true, encoding: .utf8)
print("\(archive.path)")
print("bytes: \(bytes)")
print("sha256: \(sha256)")
