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
        .package(url: "https://github.com/swiftlang/swift-markdown.git", from: "0.5.0")
    ],
    targets: [
        .target(name: "AloudUI", swiftSettings: strict),
        .target(
            name: "Prose",
            dependencies: [.product(name: "Markdown", package: "swift-markdown")],
            swiftSettings: strict),
        .target(name: "Vault", swiftSettings: strict),
        .target(name: "Speech", dependencies: ["Prose"], swiftSettings: strict),
        .executableTarget(
            name: "Aloud",
            dependencies: ["AloudUI", "Prose", "Vault", "Speech"],
            swiftSettings: strict),
        .testTarget(name: "AloudUITests", dependencies: ["AloudUI"], swiftSettings: strict),
        .testTarget(
            name: "ProseTests", dependencies: ["Prose"],
            resources: [.copy("Fixtures")], swiftSettings: strict),
        .testTarget(name: "VaultTests", dependencies: ["Vault"], swiftSettings: strict),
        .testTarget(name: "SpeechTests", dependencies: ["Speech"], swiftSettings: strict),
    ]
)
