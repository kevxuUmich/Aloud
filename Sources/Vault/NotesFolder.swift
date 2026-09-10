import Foundation

/// The folder a note lands in when no other has been chosen: Aloud's own, in the
/// Documents folder the app can write without asking, which under the sandbox is the
/// app's container. It is a root like any attached folder, so the library shows it,
/// and the one that cannot be detached.
public enum NotesFolder {
    public static let name = "Aloud Notes"
    public static var url: URL {
        FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
            .appendingPathComponent(name)
    }

    /// The folder, made if it is not there. Nil where it cannot be a folder - a file in
    /// its way, or a disk that will not take it - so the caller knows it has no home
    /// for a note rather than a path that will fail on the first write.
    @discardableResult
    public static func ensure(_ url: URL = url) -> URL? {
        let fm = FileManager.default
        try? fm.createDirectory(at: url, withIntermediateDirectories: true)
        var isDir: ObjCBool = false
        guard fm.fileExists(atPath: url.path, isDirectory: &isDir), isDir.boolValue else { return nil }
        return url
    }
}
