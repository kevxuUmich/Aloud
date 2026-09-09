import Foundation

public enum Scanner {
    static let previewBytes = 600

    public static func scan(root: URL) throws -> Folder {
        let fm = FileManager.default
        let keys: [URLResourceKey] = [.isDirectoryKey, .contentModificationDateKey, .nameKey, .fileSizeKey]
        let items = try fm.contentsOfDirectory(
            at: root, includingPropertiesForKeys: keys, options: [.skipsHiddenFiles])
        var folders: [Folder] = []
        var docs: [Document] = []
        for item in items {
            let v = try item.resourceValues(forKeys: Set(keys))
            if v.isDirectory == true {
                folders.append(try scan(root: item))
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
            documents: docs.sorted { $0.modified > $1.modified })
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
            preview: Title.stripFrontMatter(head), modified: modified, bytes: bytes, type: type)
    }

    static func headText(of url: URL) -> String {
        guard let handle = try? FileHandle(forReadingFrom: url) else { return "" }
        defer { try? handle.close() }
        let data = (try? handle.read(upToCount: previewBytes * 4)) ?? Data()
        return String(decoding: data, as: UTF8.self)
    }
}
