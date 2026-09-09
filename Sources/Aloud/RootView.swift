import AloudUI
import AppKit
import SwiftUI
import Vault

struct RootView: View {
    @Bindable var model: AppModel

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
        // The bar is always there, flush to the window's bottom edge and the full
        // width of it: it is the app's one transport, and a control that appears
        // only once something is loaded is a control nobody learns. It is the only
        // bottom inset, so the library's scroll content ends above it.
        .safeAreaInset(edge: .bottom) {
            TransportBarView(model: model)
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
                .padding(Space.l)
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
