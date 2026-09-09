import Foundation
import Prose

public enum Scanner {
    static let previewBytes = 600

    public static func scan(root: URL) throws -> Folder {
        var visited = Set<String>()
        return try scan(root: root, visited: &visited)
    }

    private static func scan(root: URL, visited: inout Set<String>) throws -> Folder {
        visited.insert(root.resolvingSymlinksInPath().path)
        let fm = FileManager.default
        let keys: [URLResourceKey] = [
            .isDirectoryKey, .contentModificationDateKey, .nameKey, .fileSizeKey,
        ]
        let items = try fm.contentsOfDirectory(
            at: root, includingPropertiesForKeys: keys, options: [.skipsHiddenFiles])
        var folders: [Folder] = []
        var docs: [Document] = []
        var unreadable: [URL] = []
        for item in items {
            let v = try item.resourceValues(forKeys: Set(keys))
            if v.isDirectory == true {
                let real = item.resolvingSymlinksInPath().path
                guard !visited.contains(real) else { continue }
                do {
                    folders.append(try scan(root: item, visited: &visited))
                } catch {
                    unreadable.append(item)
                }
            } else if let type = DocumentType(url: item) {
                docs.append(
                    document(
                        at: item, type: type, modified: v.contentModificationDate ?? .distantPast,
                        bytes: v.fileSize ?? 0))
            }
        }
        return Folder(
            url: root, name: root.lastPathComponent,
            folders: folders.sorted { $0.name.localizedStandardCompare($1.name) == .orderedAscending },
            documents: docs.sorted { $0.modified > $1.modified },
            unreadable: unreadable)
    }

    static func document(at url: URL, type: DocumentType, modified: Date, bytes: Int) -> Document {
        guard type != .pdf else {
            return Document(
                url: url, title: url.deletingPathExtension().lastPathComponent, preview: "",
                modified: modified, bytes: bytes, type: .pdf)
        }
        let head = headText(of: url)
        return Document(
            url: url,
            title: Title.from(text: head, fallback: url.deletingPathExtension().lastPathComponent),
            preview: FrontMatter.strip(head), modified: modified, bytes: bytes, type: type)
    }

    static func headText(of url: URL) -> String {
        guard let handle = try? FileHandle(forReadingFrom: url) else { return "" }
        defer { try? handle.close() }
        let data = (try? handle.read(upToCount: previewBytes * 4)) ?? Data()
        return String(decoding: trimmingPartialScalar(data), as: UTF8.self)
    }

    /// The read stops at a byte count, which can land inside a multi-byte character,
    /// and decoding that tail would put a U+FFFD at the end of every such preview.
    /// Walk back over the continuation bytes and drop the lead byte too when the
    /// sequence it opened is short.
    static func trimmingPartialScalar(_ data: Data) -> Data {
        var end = data.endIndex
        var continuations = 0
        // A lead byte can be preceded by three continuations, so the walk needs a
        // fourth pass to reach it; stopping at three lost the lead byte of every
        // complete four-byte scalar that ended exactly at the ceiling.
        while end > data.startIndex, continuations < 4 {
            let byte = data[data.index(before: end)]
            if byte & 0xC0 == 0x80 {
                continuations += 1
                end = data.index(before: end)
                continue
            }
            let expected: Int
            switch byte {
            case 0x00...0x7F: expected = 0
            case 0xC0...0xDF: expected = 1
            case 0xE0...0xEF: expected = 2
            case 0xF0...0xF7: expected = 3
            default: expected = 0
            }
            if expected == continuations { return data[data.startIndex..<data.endIndex] }
            return data[data.startIndex..<data.index(before: end)]
        }
        return data[data.startIndex..<end]
    }
}
