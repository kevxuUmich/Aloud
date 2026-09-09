// swift-tools-version: 6.2
import PackageDescription

let strict: [SwiftSetting] = [.swiftLanguageMode(.v6)]

let package = Package(
    name: "Aloud",
    platforms: [.macOS(.v26)],
    products: [
        .executable(name: "Aloud", targets: ["Aloud"])
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
    ],
    targets: [
        .target(name: "AloudUI", swiftSettings: strict),
        .target(
            name: "Prose",
            dependencies: [.product(name: "Markdown", package: "swift-markdown")],
            swiftSettings: strict),
        .target(name: "Vault", dependencies: ["Prose"], swiftSettings: strict),
        .target(name: "Speech", dependencies: ["Prose", "Vault"], swiftSettings: strict),
        .executableTarget(
            name: "Aloud",
            dependencies: [
                "AloudUI", "Prose", "Vault", "Speech",
                .product(name: "KeyboardShortcuts", package: "KeyboardShortcuts"),
            ],
            swiftSettings: strict),
        .testTarget(name: "AloudTests", dependencies: ["Aloud"], swiftSettings: strict),
        .testTarget(name: "AloudUITests", dependencies: ["AloudUI"], swiftSettings: strict),
        .testTarget(
            name: "ProseTests", dependencies: ["Prose"],
            resources: [.copy("Fixtures")], swiftSettings: strict),
        .testTarget(name: "VaultTests", dependencies: ["Vault"], swiftSettings: strict),
        .testTarget(name: "SpeechTests", dependencies: ["Speech", "Vault"], swiftSettings: strict),
    ]
)
