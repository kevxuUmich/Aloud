import SwiftUI

/// The header of a section whose voices come as one download: the title, and under
/// it the caption, the progress with Cancel, the installing spinner, or the failure
/// with Retry. Pure: strings and closures in, no model.
public struct DownloadBanner: View {
    public enum Phase: Equatable {
        case idle(String)
        case progress(Double)
        case busy(String)
        case failed(String)
    }

    let title: String
    let phase: Phase
    let onCancel: () -> Void
    let onRetry: () -> Void

    public init(title: String, phase: Phase, onCancel: @escaping () -> Void, onRetry: @escaping () -> Void) {
        self.title = title
        self.phase = phase
        self.onCancel = onCancel
        self.onRetry = onRetry
    }

    /// The floor under the phase's line, so the caption, the progress row, the install
    /// row and the failure all take the same height and the voices below the header
    /// stay where they were through the download. Installed shows nothing and keeps no
    /// space, which is nil rather than a minimum of zero.
    var phaseMinHeight: CGFloat? {
        phase == .idle("") ? nil : Size.bannerPhaseHeight
    }

    public var body: some View {
        VStack(alignment: .leading, spacing: Space.xs) {
            Text(title).font(Type.caption).foregroundStyle(Ink.soft)
            VStack(alignment: .leading, spacing: Space.xs) {
                switch phase {
                case .idle(let caption):
                    if !caption.isEmpty {
                        Text(caption)
                            .font(Type.caption)
                            .foregroundStyle(Ink.soft)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                case .progress(let fraction):
                    HStack(spacing: Space.s) {
                        ProgressView(value: fraction)
                            .progressViewStyle(.linear)
                            .accessibilityLabel("Downloading")
                        Button(Copy.cancel, action: onCancel).buttonStyle(.link)
                    }
                case .busy(let word):
                    HStack(spacing: Space.s) {
                        ProgressView().controlSize(.small)
                        Text(word).font(Type.caption).foregroundStyle(Ink.soft)
                    }
                case .failed(let message):
                    HStack(alignment: .firstTextBaseline, spacing: Space.s) {
                        Text(message)
                            .font(Type.caption)
                            .foregroundStyle(Ink.soft)
                            .fixedSize(horizontal: false, vertical: true)
                        Button(Copy.retry, action: onRetry).buttonStyle(.link)
                    }
                }
            }
            .frame(minHeight: phaseMinHeight, alignment: .topLeading)
        }
    }
}
