import Foundation

public enum Importer {
    /// What one import did: the new URLs, and the sources that could not be copied.
    public struct Imported: Sendable, Equatable {
        public let added: [URL]
        public let failed: [URL]
        public init(added: [URL], failed: [URL]) {
            self.added = added
            self.failed = failed
        }
    }

    /// Copies the supported files into `folder`, never overwriting. One file that cannot
    /// be copied is collected rather than thrown, so a bad file in a drop of ten does not
    /// cost the other nine.
    public static func importFiles(_ urls: [URL], into folder: URL) -> Imported {
        let fm = FileManager.default
        var added: [URL] = []
        var failed: [URL] = []
        for url in urls where DocumentType(url: url) != nil {
            let base = url.deletingPathExtension().lastPathComponent
            let ext = url.pathExtension
            var candidate = folder.appendingPathComponent("\(base).\(ext)")
            var n = 2
            while fm.fileExists(atPath: candidate.path) {
                candidate = folder.appendingPathComponent("\(base) \(n).\(ext)")
                n += 1
            }
            do {
                try fm.copyItem(at: url, to: candidate)
                added.append(candidate)
            } catch {
                failed.append(url)
            }
        }
        return Imported(added: added, failed: failed)
    }
}
