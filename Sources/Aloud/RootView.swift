import AloudUI
import AppKit
import SwiftUI
import Vault

struct RootView: View {
    @Bindable var model: AppModel
    /// How far down the notice reaches, its margin included; zero with no notice.
    @State private var noticeInset: CGFloat = .zero

    var body: some View {
        NavigationStack(path: $model.path) {
            LibraryView(model: model, folderURL: nil)
                .navigationDestination(for: Route.self) { route in
                    switch route {
                    case .folder(let url): LibraryView(model: model, folderURL: url)
                    case .reader(let d): ReaderView(model: model, document: d)
                    }
                }
        }
        .environment(\.noticeInset, noticeInset)
        // The bar floats at the window's foot, with a margin on its sides and its
        // bottom, while something is loaded; with nothing to play there is nothing to
        // control, and the X on the bar is what takes it away. It is the only bottom
        // inset, so the library's scroll content ends above it.
        //
        // The animation is scoped to the inset's own container and not to the stack:
        // a load lands in the same instant as the push to the reader, and an animation
        // on the stack made that push a cross-fade, with the library showing through
        // the reader while it ran.
        .safeAreaInset(edge: .bottom) {
            VStack(spacing: Space.none) {
                if model.current != nil {
                    TransportBarView(model: model)
                        .padding([.horizontal, .bottom], Space.barInset)
                        .transition(.move(edge: .bottom).combined(with: .opacity))
                }
            }
            .animation(Motion.ease, value: model.current == nil)
        }
        .overlay(alignment: .top) {
            if let n = model.notice {
                // A tap gesture on a plain view is invisible to the keyboard and to
                // VoiceOver; the dismissal is a button, styled as the notice itself.
                Button {
                    model.notice = nil
                } label: {
                    Notice(n)
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Dismiss notice: \(n)")
                .padding([.horizontal, .top], Space.l)
                .onGeometryChange(for: CGFloat.self) {
                    $0.size.height
                } action: {
                    noticeInset = $0
                }
                .onDisappear { noticeInset = .zero }
            }
        }
        // A notice can arrive while the reader is elsewhere on screen, so it is spoken
        // rather than only drawn.
        // `initial: true`, because a notice set in the model's init - unreachable vault
        // roots - is already there when the view first appears and would never change.
        .onChange(of: model.notice, initial: true) { _, now in
            guard let now else { return }
            NSAccessibility.post(
                element: NSApp.mainWindow ?? NSApp as Any, notification: .announcementRequested,
                userInfo: [
                    .announcement: now,
                    .priority: NSAccessibilityPriorityLevel.high.rawValue,
                ])
        }
        .frame(minWidth: Size.minWindow.width, minHeight: Size.minWindow.height)
        .task { model.start() }
    }
}

extension EnvironmentValues {
    /// How much of the top of the content the notice floats over, zero with none. The
    /// notice stays over the content rather than taking a band of its own, and each
    /// scrolling surface starts its content this far down instead, so nothing sits
    /// under the notice at rest and everything scrolls beneath it. Laid over the
    /// content alone, the capsule sat on the reader's first line and on the tops of
    /// the cards; given a band in the safe area, it moved the reader's scroll view off
    /// the toolbar, which then drew a hard line under itself on every document.
    @Entry var noticeInset: CGFloat = .zero
}
