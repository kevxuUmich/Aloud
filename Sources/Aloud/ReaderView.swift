import SwiftUI
import Vault

struct ReaderView: View {
    var model: AppModel
    var document: Document
    var body: some View { Text(document.title) }
}
