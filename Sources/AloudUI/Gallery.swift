import SwiftUI

public struct Gallery: View {
    public static let sections = [
        "GlassBar", "GlassBar docked", "Card", "FolderCard", "IconButton", "TransportButton",
        "RateButton", "Scrubber", "EmptyState no vault", "EmptyState empty vault", "Notice",
        "ListRow", "VoiceRow",
    ]
    public init() {}
    public var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: Space.xxl) {
                section("GlassBar") {
                    GlassBar {
                        HStack(spacing: Space.l) {
                            Text("Left")
                            Spacer()
                            Text("Right")
                        }
                    }
                }
                section("GlassBar docked") {
                    GlassBar(docked: true) {
                        HStack(spacing: Space.l) {
                            Text("Left")
                            Spacer()
                            Text("Right")
                        }
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
                section("EmptyState no vault") {
                    EmptyState(kind: .noVault, hotkey: "Ctrl+Option+Space", onPrimary: {}, onSecondary: {})
                }
                section("EmptyState empty vault") {
                    EmptyState(
                        kind: .emptyVault, hotkey: "Ctrl+Option+Space", onPrimary: {}, onSecondary: {})
                }
                section("Notice") { Notice("Voice not available, using the system default") }
                section("ListRow") {
                    VStack(alignment: .leading, spacing: Space.none) {
                        ListRow(title: "Essays", status: "12 documents", symbol: "folder.fill")
                        ListRow(title: "It's been a fast year.", status: "~8 min", symbol: "doc.fill")
                        ListRow(title: "Finished one", status: "Finished", symbol: "doc.fill")
                    }
                }
                section("VoiceRow") {
                    VStack(alignment: .leading, spacing: Space.none) {
                        VoiceRow(
                            name: "Samantha", region: "United States", quality: "Premium",
                            isSelected: true, onPreview: {}, onPick: {})
                        VoiceRow(
                            name: "Daniel", region: "United Kingdom", quality: "Enhanced",
                            isSelected: false, onPreview: {}, onPick: {})
                        VoiceRow(
                            name: "Majed", region: nil, quality: "Default",
                            isSelected: false, onPreview: {}, onPick: {})
                    }
                }
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
