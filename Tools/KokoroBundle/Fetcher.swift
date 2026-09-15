import Foundation

public enum FetchError: Error, Equatable {
    case mismatch(String)
    case http(Int, String)
}

/// Fills the inputs folder against the pinned list. A file already there with the right
/// size and hash is left alone; anything else is downloaded to a temporary file, moved
/// into place, and checked again before it counts.
///
/// The four acoustic buckets share their weights byte for byte, so a pinned input whose
/// hash is already on disk under the inputs folder is linked from that copy instead of
/// being downloaded again: without that the inputs folder would cost about 540 MB of
/// downloads rather than 170 MB.
public struct Fetcher: Sendable {
    public typealias Download = @Sendable (URL) async throws -> URL

    public let inputs: URL
    let download: Download

    public init(inputs: URL, download: @escaping Download = Fetcher.viaURLSession) {
        self.inputs = inputs
        self.download = download
    }

    /// The default download: the shared session, to a temporary file, refusing anything
    /// but a 200.
    public static let viaURLSession: Download = { url in
        let (file, response) = try await URLSession.shared.download(from: url)
        if let http = response as? HTTPURLResponse, http.statusCode != 200 {
            try? FileManager.default.removeItem(at: file)
            throw FetchError.http(http.statusCode, url.absoluteString)
        }
        return file
    }

    public func isPresent(_ input: PinnedInput) throws -> Bool {
        let url = inputs.appendingPathComponent(input.path)
        guard FileManager.default.fileExists(atPath: url.path) else { return false }
        guard try url.resourceValues(forKeys: [.fileSizeKey]).fileSize == input.bytes else { return false }
        return try Digest.sha256(ofFileAt: url) == input.sha256
    }

    public func fetch(_ pinned: [PinnedInput], log: @escaping @Sendable (String) -> Void) async throws {
        // Everything already verified on disk first, so a later input can be linked from
        // a copy an earlier run fetched and not only from one this run downloaded.
        var onDisk: [String: URL] = [:]
        var wanted: [PinnedInput] = []
        for input in pinned {
            if try isPresent(input) {
                onDisk[input.sha256] = inputs.appendingPathComponent(input.path)
            } else {
                wanted.append(input)
            }
        }
        for input in wanted {
            let destination = inputs.appendingPathComponent(input.path)
            try FileManager.default.createDirectory(
                at: destination.deletingLastPathComponent(), withIntermediateDirectories: true)
            try? FileManager.default.removeItem(at: destination)
            if let twin = onDisk[input.sha256] {
                log("linking \(input.path)")
                try link(twin, to: destination)
            } else {
                log("fetching \(input.path)")
                let temporary = try await download(input.url)
                try FileManager.default.moveItem(at: temporary, to: destination)
            }
            guard try isPresent(input) else {
                try? FileManager.default.removeItem(at: destination)
                throw FetchError.mismatch(input.path)
            }
            onDisk[input.sha256] = destination
        }
    }

    /// A hard link, so the shared weights cost one copy on disk, falling back to a copy
    /// on a filesystem that will not link.
    private func link(_ source: URL, to destination: URL) throws {
        do {
            try FileManager.default.linkItem(at: source, to: destination)
        } catch {
            try FileManager.default.copyItem(at: source, to: destination)
        }
    }
}
