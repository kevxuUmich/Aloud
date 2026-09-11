import SwiftUI

/// The landing state: the whole window, not a card floating in it. It is the first
/// thing a new user sees, so it says what the app is, offers the two ways in, and
/// names the two that have no button - the drop target and the system-wide hotkey.
public struct EmptyState: View {
    /// Two landings, one shape: no folder chosen yet, or a folder with nothing in it
    /// this app can read.
    public enum Kind { case noVault, emptyVault }

    let kind: Kind
    /// The hotkey as the user has it bound. `AloudUI` cannot see KeyboardShortcuts,
    /// so the app reads the binding and passes the text down.
    let hotkey: String
    let onPrimary: () -> Void
    let onSecondary: () -> Void

    public init(
        kind: Kind, hotkey: String, onPrimary: @escaping () -> Void,
        onSecondary: @escaping () -> Void
    ) {
        self.kind = kind
        self.hotkey = hotkey
        self.onPrimary = onPrimary
        self.onSecondary = onSecondary
    }

    public var body: some View {
        VStack(spacing: Space.xl) {
            ApertureGlyph()
                .frame(width: Size.landingGlyph, height: Size.landingGlyph)
                .foregroundStyle(Ink.landingGlyph)
                .accessibilityHidden(true)
            Text("Aloud").font(Type.landingTitle)
            Text(
                kind == .noVault
                    ? "Point it at a folder of notes, or paste anything, and listen."
                    : "This folder has no .md, .txt or .pdf files yet."
            )
            .font(Type.landingBody).foregroundStyle(Ink.soft)
            .multilineTextAlignment(.center)
            .frame(maxWidth: Size.landingMeasure)
            HStack(spacing: Space.m) {
                Button(kind == .noVault ? "Choose a folder" : "Import files", action: onPrimary)
                    .buttonStyle(.glassProminent)
                Button("Paste from clipboard", action: onSecondary).buttonStyle(.glass)
            }
            Text(
                "Drop files or folders anywhere in this window. \(hotkey) reads the clipboard from any app."
            )
            .font(Type.caption).foregroundStyle(Ink.soft)
            .multilineTextAlignment(.center)
            .frame(maxWidth: Size.landingMeasure)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .padding(Space.xxxl)
    }
}
