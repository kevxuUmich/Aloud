import Foundation

public enum FetchError: Error, Equatable {
    case mismatch(String)
    case http(Int, String)
}

/// Fills the inputs folder against the pinned list. A file already there with the right
/// size and hash is left alone; anything else is downloaded to a temporary file, moved
/// into place, and checked again before it counts.
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
        for input in pinned {
            if try isPresent(input) { continue }
            log("fetching \(input.path)")
            let temporary = try await download(input.url)
            let destination = inputs.appendingPathComponent(input.path)
            try FileManager.default.createDirectory(
                at: destination.deletingLastPathComponent(), withIntermediateDirectories: true)
            try? FileManager.default.removeItem(at: destination)
            try FileManager.default.moveItem(at: temporary, to: destination)
            guard try isPresent(input) else {
                try? FileManager.default.removeItem(at: destination)
                throw FetchError.mismatch(input.path)
            }
        }
    }
}
