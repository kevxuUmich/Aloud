import Foundation
import Vault

enum Route: Hashable {
    case folder(URL)
    case reader(Document)
}
