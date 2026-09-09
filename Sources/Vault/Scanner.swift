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
        return String(decoding: data, as: UTF8.self)
    }
}
