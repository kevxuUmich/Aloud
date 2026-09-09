import AloudUI
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
        .safeAreaInset(edge: .bottom) {
            if model.current != nil {
                TransportBarView(model: model).padding(Space.l)
            }
        }
        .overlay(alignment: .top) {
            if let n = model.notice {
                Notice(n).padding(Space.l).onTapGesture { model.notice = nil }
            }
        }
        .frame(minWidth: Size.minWindow.width, minHeight: Size.minWindow.height)
        .task { model.start() }
    }
}
