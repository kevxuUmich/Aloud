import Vault

enum Route: Hashable {
    case folder(Folder)
    case reader(Document)
}
