import Foundation

public enum Paths {
    /// True when `path` is `root` itself or lies under it. The comparison is by path
    /// component and not by string prefix, so `/Users/k/NotesArchive` is not inside
    /// `/Users/k/Notes`.
    public static func isInside(_ path: String, root: String) -> Bool {
        let root = root.hasSuffix("/") ? String(root.dropLast()) : root
        return path == root || path.hasPrefix(root + "/")
    }
}
