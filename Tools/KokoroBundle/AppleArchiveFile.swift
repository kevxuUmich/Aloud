import AppleArchive
import Foundation
import System

public enum ArchiveError: Error, Equatable {
    case cannotOpen(String)
    case cannotWrite(String)
    case cannotRead(String)
}

/// One Apple Archive of a directory, LZFSE compressed, the format the model bundle
/// ships in. The field key set is `TYP,PAT,DAT,MOD`: type, path, data and mode, and
/// none of the times or owners the default set carries, so the same tree gives the same
/// bytes on any machine.
public enum AppleArchiveFile {
    static let keySet = "TYP,PAT,DAT,MOD"

    public static func compress(directory: URL, to archive: URL) throws {
        guard
            let file = ArchiveByteStream.fileStream(
                path: FilePath(archive.path), mode: .writeOnly, options: [.create, .truncate],
                permissions: FilePermissions(rawValue: 0o644))
        else { throw ArchiveError.cannotWrite(archive.path) }
        defer { try? file.close() }
        guard let compression = ArchiveByteStream.compressionStream(using: .lzfse, writingTo: file) else {
            throw ArchiveError.cannotWrite(archive.path)
        }
        defer { try? compression.close() }
        guard let encoder = ArchiveStream.encodeStream(writingTo: compression) else {
            throw ArchiveError.cannotWrite(archive.path)
        }
        defer { try? encoder.close() }
        guard let keys = ArchiveHeader.FieldKeySet(keySet) else { throw ArchiveError.cannotWrite(keySet) }
        try encoder.writeDirectoryContents(archiveFrom: FilePath(directory.path), keySet: keys)
    }

    /// Extracts the archive's tree into `directory`, creating it. The archive is trusted
    /// only after its checksum matched, which is the caller's job.
    public static func extract(archive: URL, into directory: URL) throws {
        guard
            let file = ArchiveByteStream.fileStream(
                path: FilePath(archive.path), mode: .readOnly, options: [],
                permissions: FilePermissions(rawValue: 0o644))
        else { throw ArchiveError.cannotOpen(archive.path) }
        defer { try? file.close() }
        guard let decompression = ArchiveByteStream.decompressionStream(readingFrom: file) else {
            throw ArchiveError.cannotRead(archive.path)
        }
        defer { try? decompression.close() }
        guard let decoder = ArchiveStream.decodeStream(readingFrom: decompression) else {
            throw ArchiveError.cannotRead(archive.path)
        }
        defer { try? decoder.close() }
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        guard
            let extractor = ArchiveStream.extractStream(
                extractingTo: FilePath(directory.path), flags: [.ignoreOperationNotPermitted])
        else { throw ArchiveError.cannotWrite(directory.path) }
        defer { try? extractor.close() }
        _ = try ArchiveStream.process(readingFrom: decoder, writingTo: extractor)
    }
}
