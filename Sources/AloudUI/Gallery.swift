import SwiftUI

public struct Gallery: View {
    public static let sections = [
        "GlassBar", "Card", "FolderCard", "IconButton", "TransportButton",
        "RateButton", "Scrubber", "EmptyState", "Notice",
    ]
    public init() {}
    public var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: Space.xxl) {
                section("GlassBar") {
                    GlassBar {
                        Text("Left"); Spacer(); Text("Right")
                    }
                }
                section("Card") {
                    HStack(spacing: Space.xl) {
                        Card(title: "It's been a fast year.", preview: Self.lorem, status: "~8 min")
                        Card(
                            title: "Managing Agents, From First Principles", preview: Self.lorem,
                            status: "3:12 left")
                        Card(title: "Finished one", preview: Self.lorem, status: "Finished")
                    }
                }
                section("FolderCard") {
                    HStack(spacing: Space.xl) {
                        FolderCard(name: "untitled folder", count: 0)
                        FolderCard(name: "Essays", count: 12)
                    }
                }
                section("IconButton") {
                    HStack {
                        IconButton("plus", label: "New") {}
                        IconButton("magnifyingglass", label: "Search") {}
                    }
                }
                section("TransportButton") {
                    HStack {
                        TransportButton(.back15) {}
                        TransportButton(.play) {}
                        TransportButton(.pause) {}
                        TransportButton(.forward15) {}
                    }
                }
                section("RateButton") {
                    RateButton(label: "1x", all: ["0.75x", "1x", "1.25x"], onCycle: {}, onPick: { _ in })
                }
                section("Scrubber") {
                    Scrubber(progress: 0.07, elapsed: "0:34", remaining: "~8:06") { _ in }
                }
                section("EmptyState") { EmptyState(onPickFolder: {}, onPaste: {}) }
                section("Notice") { Notice("Voice not available, using the system default") }
            }
            .padding(Space.xxl)
        }
    }
    func section(_ name: String, @ViewBuilder _ content: () -> some View) -> some View {
        VStack(alignment: .leading, spacing: Space.m) {
            Text(name).font(Type.caption).foregroundStyle(Ink.soft)
            content()
        }
    }
    static let lorem = String(
        repeating:
            "nobody really teaches you research. you get a desk, a problem someone else picked. ",
        count: 12)
}
