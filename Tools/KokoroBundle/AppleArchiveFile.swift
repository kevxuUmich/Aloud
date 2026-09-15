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
        var finished = false
        defer { if !finished { try? file.close() } }
        guard let compression = ArchiveByteStream.compressionStream(using: .lzfse, writingTo: file) else {
            throw ArchiveError.cannotWrite(archive.path)
        }
        defer { if !finished { try? compression.close() } }
        guard let encoder = ArchiveStream.encodeStream(writingTo: compression) else {
            throw ArchiveError.cannotWrite(archive.path)
        }
        defer { if !finished { try? encoder.close() } }
        guard let keys = ArchiveHeader.FieldKeySet(keySet) else { throw ArchiveError.cannotWrite(keySet) }
        try encoder.writeDirectoryContents(archiveFrom: FilePath(directory.path), keySet: keys)

        // The encoder's end-of-archive marker and the compressor's trailer are only
        // flushed on close, so a failure here means a truncated archive: closes are
        // explicit and checked, in the order encoder, then compression, then file, and
        // the defers above only run if one of these throws partway through.
        do {
            try encoder.close()
            try compression.close()
            try file.close()
            finished = true
        } catch {
            throw ArchiveError.cannotWrite(archive.path)
        }
    }

    /// Extracts the archive's tree into `directory`, creating it.
    ///
    /// Precondition: the archive's SHA-256 must already have been checked against its
    /// pinned value before this is called, never after -- this function trusts the
    /// bytes it is given and does not verify them itself.
    ///
    /// Extraction merges into an existing destination rather than replacing it, and a
    /// failure partway through leaves a partial tree behind at `directory`. A caller
    /// should extract into a fresh scratch folder and move that folder into place only
    /// once this call has returned successfully.
    ///
    /// The call blocks the calling thread for as long as extraction takes -- seconds
    /// for a 159 MB archive -- so it must not run on the main actor.
    public static func extract(archive: URL, into directory: URL) throws {
        guard
            let file = ArchiveByteStream.fileStream(
                path: FilePath(archive.path), mode: .readOnly, options: [],
                permissions: FilePermissions(rawValue: 0o644))
        else { throw ArchiveError.cannotOpen(archive.path) }
        var finished = false
        defer { if !finished { try? file.close() } }
        guard let decompression = ArchiveByteStream.decompressionStream(readingFrom: file) else {
            throw ArchiveError.cannotRead(archive.path)
        }
        defer { if !finished { try? decompression.close() } }
        guard let decoder = ArchiveStream.decodeStream(readingFrom: decompression) else {
            throw ArchiveError.cannotRead(archive.path)
        }
        defer { if !finished { try? decoder.close() } }
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        guard
            let extractor = ArchiveStream.extractStream(
                extractingTo: FilePath(directory.path), flags: [.ignoreOperationNotPermitted])
        else { throw ArchiveError.cannotWrite(directory.path) }
        defer { if !finished { try? extractor.close() } }
        _ = try ArchiveStream.process(readingFrom: decoder, writingTo: extractor)

        // Same reasoning as compress: an I/O failure at flush must not be swallowed by
        // a bare `defer { try? ... }`, so closes are explicit and checked, in the order
        // extractor, then decoder, then decompression, then file.
        do {
            try extractor.close()
            try decoder.close()
            try decompression.close()
            try file.close()
            finished = true
        } catch {
            throw ArchiveError.cannotRead(archive.path)
        }
    }
}
