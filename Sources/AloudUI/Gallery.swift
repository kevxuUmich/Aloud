import SwiftUI

public struct Gallery: View {
    public static let sections = [
        "GlassBar", "Card", "Thumb", "FolderCard", "IconButton", "TransportButton",
        "RateButton", "Scrubber", "EmptyState no vault", "EmptyState empty vault", "Notice",
        "ListRow", "VoiceRow", "ClipboardCard", "ApertureGlyph", "VolumeControl",
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
                section("Card") {
                    HStack(spacing: Space.xl) {
                        Card(title: "It's been a fast year.", preview: Self.lorem, status: "~8 min")
                        Card(
                            title: "Managing Agents, From First Principles", preview: Self.lorem,
                            status: "3:12 left")
                        Card(title: "Finished one", preview: Self.lorem, status: "Finished")
                        Card(
                            title: "Kept for later", preview: Self.lorem, status: "~8 min",
                            bookmarked: true)
                    }
                }
                section("Thumb") {
                    HStack(alignment: .bottom, spacing: Space.xl) {
                        Thumb(preview: Self.lorem, scale: .card)
                        Thumb(preview: Self.lorem, scale: .bar)
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
                        TransportButton(.back) {}
                        TransportButton(.play) {}
                        TransportButton(.pause) {}
                        TransportButton(.forward) {}
                    }
                }
                section("VolumeControl") {
                    HStack(spacing: Space.xl) {
                        VolumeControl(volume: .constant(0), onCommit: {})
                        VolumeControl(volume: .constant(0.5), onCommit: {})
                        VolumeControl(volume: .constant(1), onCommit: {})
                    }
                }
                section("RateButton") {
                    RateButton(label: "1x", all: ["0.75x", "1x", "1.25x"], onCycle: {}, onPick: { _ in })
                }
                section("Scrubber") {
                    Scrubber(progress: 0.07, elapsed: "0:34", remaining: "~8:06") { _ in }
                }
                section("EmptyState no vault") {
                    EmptyState(kind: .noVault, hotkey: "Option+Space", onPrimary: {}, onSecondary: {})
                }
                section("EmptyState empty vault") {
                    EmptyState(
                        kind: .emptyVault, hotkey: "Option+Space", onPrimary: {}, onSecondary: {})
                }
                section("Notice") { Notice("Voice not available, using the system default") }
                section("ListRow") {
                    VStack(alignment: .leading, spacing: Space.none) {
                        ListRow(title: "Essays", status: "12 documents", symbol: "folder.fill")
                        ListRow(title: "It's been a fast year.", status: "~8 min", symbol: "doc.fill")
                        ListRow(title: "Finished one", status: "Finished", symbol: "doc.fill")
                        ListRow(
                            title: "Kept for later", status: "~8 min", symbol: "doc.fill",
                            bookmarked: true)
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
                        VoiceRow(
                            name: "Jamie", region: "United Kingdom", quality: "Enhanced",
                            badge: "116 MB", isSelected: false, onPreview: {}, onPick: {})
                        VoiceRow(
                            name: "Kate", region: "United Kingdom", quality: "Enhanced",
                            badge: "50 MB", isSelected: false, isInstalled: false,
                            onPreview: {}, onPick: {})
                    }
                }
                section("ClipboardCard") {
                    VStack(alignment: .leading, spacing: Space.l) {
                        ClipboardCard(
                            title: "It's been a fast year.", subtitle: "From clipboard · ~3 min · 412 words",
                            transport: .ready, progress: 0, elapsed: "0:00", remaining: "~2:35",
                            onPlay: {}, onBack: {}, onForward: {}, onSeek: { _ in })
                        ClipboardCard(
                            title: "It's been a fast year.", subtitle: "From clipboard · ~3 min · 412 words",
                            transport: .playing(isPlaying: true), progress: 0.3, elapsed: "0:46",
                            remaining: "~1:49", onPlay: {}, onBack: {}, onForward: {}, onSeek: { _ in })
                        ClipboardCard(
                            title: "Nothing to read", subtitle: "The clipboard has no text",
                            transport: .disabled, progress: 0, elapsed: "0:00", remaining: "~0:00",
                            onPlay: {}, onBack: {}, onForward: {}, onSeek: { _ in })
                        ClipboardCard(
                            title: "It's been a fast year.", subtitle: "Pick a folder in Aloud first",
                            transport: .ready, progress: 0, elapsed: "0:00", remaining: "~2:35",
                            onPlay: {}, onBack: {}, onForward: {}, onSeek: { _ in })
                    }
                }

                section("ApertureGlyph") {
                    HStack(spacing: Space.xl) {
                        ApertureGlyph().frame(width: Size.icon, height: Size.icon)
                        ApertureGlyph().frame(width: Size.control, height: Size.control)
                        ApertureGlyph().frame(width: Size.landingGlyph, height: Size.landingGlyph)
                            .foregroundStyle(Ink.landingGlyph)
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
