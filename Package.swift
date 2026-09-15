// swift-tools-version: 6.2
import PackageDescription

let strict: [SwiftSetting] = [.swiftLanguageMode(.v6)]

let package = Package(
    name: "Aloud",
    platforms: [.macOS(.v26)],
    products: [
        .executable(name: "Aloud", targets: ["Aloud"]),
        // The four modules as products, for the Xcode target: `project.yml` compiles
        // `Sources/Aloud` itself and reaches these by product name, and a target that
        // is not a product is invisible to it - "Missing package product 'AloudUI'".
        // `swift build` never needed them, which is how they came to be missing.
        .library(name: "AloudUI", targets: ["AloudUI"]),
        .library(name: "Prose", targets: ["Prose"]),
        .library(name: "Vault", targets: ["Vault"]),
        .library(name: "Speech", targets: ["Speech"]),
        // The bundle tool's library, a product so plan 3's Xcode target can link its
        // archive reader.
        .library(name: "KokoroBundle", targets: ["KokoroBundle"]),
        .library(name: "Kokoro", targets: ["Kokoro"]),
    ],
    dependencies: [
        .package(url: "https://github.com/swiftlang/swift-markdown.git", from: "0.5.0"),
        // Pinned rather than `from: "2.0.0"`: every tag from 1.16.0 up carries a
        // `#Preview` in its Recorder, and the `PreviewsMacros` plugin that expands one
        // ships with Xcode, not with the Command Line Tools this builds against. 1.15.0
        // is the newest tag that compiles here, and it has the whole API Aloud uses.
        // `project.yml` pins the same version for the Xcode target, which compiles
        // `Sources/Aloud` itself rather than reaching it as a product of this package;
        // the two pins are one decision and move together.
        .package(url: "https://github.com/sindresorhus/KeyboardShortcuts", exact: "1.15.0"),
        // The Kokoro SDK, Aloud's fork, pinned by exact revision. It pins its own
        // MisakiSwift fork by revision, and SwiftPM refuses a version range over a
        // package that does, so this stays a revision too.
        .package(
            url: "https://github.com/kevinxu-cmd/kokoro-coreml.git",
            revision: "2932a26444b8deba2a6be6c0aa45c0424efaefe1"),
    ],
    targets: [
        .target(name: "AloudUI", swiftSettings: strict),
        .target(
            name: "Prose",
            dependencies: [.product(name: "Markdown", package: "swift-markdown")],
            swiftSettings: strict),
        .target(name: "Vault", dependencies: ["Prose"], swiftSettings: strict),
        .target(name: "Speech", dependencies: ["Prose", "Vault"], swiftSettings: strict),
        // The second engine, beside Speech: the catalogue, the model store, the SDK
        // actor, the audio player and the provider. Speech never imports it.
        .target(
            name: "Kokoro",
            dependencies: ["Speech", "KokoroBundle", .product(name: "KokoroTTS", package: "kokoro-coreml")],
            swiftSettings: strict),
        .executableTarget(
            name: "Aloud",
            dependencies: [
                "AloudUI", "Prose", "Vault", "Speech", "Kokoro",
                .product(name: "KeyboardShortcuts", package: "KeyboardShortcuts"),
            ],
            swiftSettings: strict),
        // The model bundle tool lives under Tools/ rather than Sources/: it is not part
        // of the app, it produces the archive the app downloads.
        .target(name: "KokoroBundle", path: "Tools/KokoroBundle", swiftSettings: strict),
        .executableTarget(
            name: "kokoro-bundle", dependencies: ["KokoroBundle"], path: "Tools/kokoro-bundle",
            swiftSettings: strict),
        .testTarget(name: "AloudTests", dependencies: ["Aloud", "AloudUI"], swiftSettings: strict),
        .testTarget(name: "AloudUITests", dependencies: ["AloudUI"], swiftSettings: strict),
        .testTarget(
            name: "ProseTests", dependencies: ["Prose"],
            resources: [.copy("Fixtures")], swiftSettings: strict),
        .testTarget(name: "VaultTests", dependencies: ["Vault"], swiftSettings: strict),
        .testTarget(name: "SpeechTests", dependencies: ["Speech", "Vault"], swiftSettings: strict),
        .testTarget(
            name: "KokoroTests", dependencies: ["Kokoro", "Speech", "KokoroBundle"], swiftSettings: strict),
        .testTarget(
            name: "KokoroBundleTests",
            dependencies: ["KokoroBundle", .product(name: "KokoroTTS", package: "kokoro-coreml")],
            resources: [.copy("Fixtures")], swiftSettings: strict),
    ]
)
