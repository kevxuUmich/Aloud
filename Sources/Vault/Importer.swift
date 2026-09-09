import Foundation

public enum Importer {
    /// Copies the supported files into `folder`, never overwriting; returns the new URLs.
    public static func importFiles(_ urls: [URL], into folder: URL) throws -> [URL] {
        let fm = FileManager.default
        var out: [URL] = []
        for url in urls where DocumentType(url: url) != nil {
            let base = url.deletingPathExtension().lastPathComponent
            let ext = url.pathExtension
            var candidate = folder.appendingPathComponent("\(base).\(ext)")
            var n = 2
            while fm.fileExists(atPath: candidate.path) {
                candidate = folder.appendingPathComponent("\(base) \(n).\(ext)")
                n += 1
            }
            try fm.copyItem(at: url, to: candidate)
            out.append(candidate)
        }
        return out
    }
}
