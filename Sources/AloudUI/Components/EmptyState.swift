import SwiftUI

public struct EmptyState: View {
    let onPickFolder: () -> Void
    let onPaste: () -> Void
    public init(onPickFolder: @escaping () -> Void, onPaste: @escaping () -> Void) {
        self.onPickFolder = onPickFolder
        self.onPaste = onPaste
    }
    public var body: some View {
        VStack(spacing: Space.l) {
            Text("Aloud reads your files to you.").font(Type.title)
            HStack(spacing: Space.m) {
                Button("Pick a folder to read from", action: onPickFolder).buttonStyle(
                    .glassProminent)
                Button("Paste anything", action: onPaste).buttonStyle(.glass)
            }
        }
        .padding(Space.xxl)
        .glassEffect(.regular, in: .rect(cornerRadius: Radius.l))
    }
}
