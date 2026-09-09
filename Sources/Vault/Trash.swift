import Foundation

public enum Trash {
    public static func move(_ document: Document) throws -> URL {
        var moved: NSURL?
        try FileManager.default.trashItem(at: document.url, resultingItemURL: &moved)
        return (moved as URL?) ?? document.url
    }
}
