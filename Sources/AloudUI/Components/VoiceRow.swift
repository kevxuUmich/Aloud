import SwiftUI

/// One voice in the picker: a preview button, then the name and its particulars,
/// which are themselves the button that picks it.
public struct VoiceRow: View {
    let name: String
    let region: String?
    let quality: String
    let isSelected: Bool
    let onPreview: () -> Void
    let onPick: () -> Void

    public init(
        name: String, region: String?, quality: String, isSelected: Bool,
        onPreview: @escaping () -> Void, onPick: @escaping () -> Void
    ) {
        self.name = name
        self.region = region
        self.quality = quality
        self.isSelected = isSelected
        self.onPreview = onPreview
        self.onPick = onPick
    }

    public var body: some View {
        HStack(spacing: Space.m) {
            Button(action: onPreview) { Image(systemName: "play.circle") }
                .buttonStyle(.borderless)
                .accessibilityLabel("Preview \(name)")
            Button(action: onPick) {
                HStack(spacing: Space.m) {
                    VStack(alignment: .leading, spacing: Space.xs) {
                        Text(name).font(Type.cardTitle)
                        HStack(spacing: Space.s) {
                            if let region {
                                Text(region).font(Type.caption).foregroundStyle(Ink.soft)
                            }
                            Text(quality).font(Type.caption).foregroundStyle(Ink.soft)
                        }
                    }
                    Spacer()
                    if isSelected { Image(systemName: "checkmark").accessibilityHidden(true) }
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel(Self.pickLabel(name, region, quality, isSelected))
        }
        .padding(.vertical, Space.s)
    }

    /// VoiceOver reads the whole row from the pick button, so the region and quality
    /// beside the name have to be in its label rather than left as loose text.
    static func pickLabel(_ name: String, _ region: String?, _ quality: String, _ isSelected: Bool)
        -> String
    {
        ([name] + [region].compactMap { $0 } + [quality] + (isSelected ? ["selected"] : []))
            .joined(separator: ", ")
    }
}
