import SwiftUI

/// One voice in the picker: a preview button, then the name and its particulars,
/// which are themselves the button that picks it. A recommended voice that is not
/// installed yet is the same row with a download arrow in place of the preview, and
/// both buttons take the reader to where it is downloaded.
public struct VoiceRow: View {
    let name: String
    let region: String?
    let quality: String
    /// A word or two beside the name: a recommended voice's download size.
    let badge: String?
    let isSelected: Bool
    let isInstalled: Bool
    let onPreview: () -> Void
    let onPick: () -> Void

    public init(
        name: String, region: String?, quality: String, badge: String? = nil,
        isSelected: Bool, isInstalled: Bool = true,
        onPreview: @escaping () -> Void, onPick: @escaping () -> Void
    ) {
        self.name = name
        self.region = region
        self.quality = quality
        self.badge = badge
        self.isSelected = isSelected
        self.isInstalled = isInstalled
        self.onPreview = onPreview
        self.onPick = onPick
    }

    /// The caption a voice that is not installed carries in place of its quality.
    public static let downloadCaption = "Download"

    public var body: some View {
        HStack(spacing: Space.m) {
            Button(action: isInstalled ? onPreview : onPick) {
                Image(systemName: isInstalled ? "play.circle" : "arrow.down.circle")
            }
            .buttonStyle(.borderless)
            .accessibilityLabel(isInstalled ? "Preview \(name)" : "Download \(name)")
            Button(action: onPick) {
                HStack(spacing: Space.m) {
                    VStack(alignment: .leading, spacing: Space.xs) {
                        HStack(spacing: Space.s) {
                            Text(name).font(Type.cardTitle)
                            if let badge { Badge(badge) }
                        }
                        HStack(spacing: Space.s) {
                            if let region {
                                Text(region).font(Type.caption).foregroundStyle(Ink.soft)
                            }
                            Text(isInstalled ? quality : Self.downloadCaption)
                                .font(Type.caption)
                                .foregroundStyle(isInstalled ? Ink.soft : Ink.accent)
                        }
                    }
                    Spacer()
                    if isSelected { Image(systemName: "checkmark").accessibilityHidden(true) }
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel(Self.pickLabel(name, region, quality, badge, isSelected, isInstalled))
        }
        .padding(.vertical, Space.s)
    }

    /// VoiceOver reads the whole row from the pick button, so the region, quality and
    /// badge beside the name have to be in its label rather than left as loose text.
    static func pickLabel(
        _ name: String, _ region: String?, _ quality: String, _ badge: String?, _ isSelected: Bool,
        _ isInstalled: Bool
    ) -> String {
        ([name] + [region].compactMap { $0 } + [quality] + [badge].compactMap { $0 }
            + (isSelected ? ["selected"] : []) + (isInstalled ? [] : ["not installed, download"]))
            .joined(separator: ", ")
    }
}

/// A small capsule of caption text in the accent colour: the size beside a
/// recommended voice's name.
public struct Badge: View {
    let text: String
    public init(_ text: String) { self.text = text }
    public var body: some View {
        Text(text)
            .font(Type.badge)
            .foregroundStyle(Ink.accent)
            .padding(.horizontal, Space.s).padding(.vertical, Space.xs)
            .background(Ink.badge, in: Capsule())
    }
}
