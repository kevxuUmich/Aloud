import Foundation

/// The real downloader: one background `URLSession`, so the 159 MB keeps arriving with
/// the window closed and even with the app quit, and a launch that finds the task still
/// running picks it up. Delegate callbacks arrive on the session's queue and are hopped
/// to the main actor; the finished file is moved before the callback returns, as the
/// session requires.
public final class URLSessionKokoroDownloader: NSObject, KokoroDownloading, URLSessionDownloadDelegate {
    private let identifier: String
    private let lock = NSLock()
    private var session: URLSession?
    private var task: URLSessionDownloadTask?
    private var destination: URL?
    private weak var delegate: (any KokoroDownloadDelegate)?

    public init(identifier: String = "design.kevxu.aloud.kokoro") {
        self.identifier = identifier
        super.init()
    }

    private func makeSession() -> URLSession {
        lock.lock()
        defer { lock.unlock() }
        if let session { return session }
        let configuration = URLSessionConfiguration.background(withIdentifier: identifier)
        configuration.isDiscretionary = false
        configuration.sessionSendsLaunchEvents = false
        let s = URLSession(configuration: configuration, delegate: self, delegateQueue: nil)
        session = s
        return s
    }

    public func download(
        _ url: URL, to destination: URL, resumeData: Data?, delegate: any KokoroDownloadDelegate
    ) {
        let session = makeSession()
        lock.lock()
        self.destination = destination
        self.delegate = delegate
        let t = resumeData.map { session.downloadTask(withResumeData: $0) } ?? session.downloadTask(with: url)
        task = t
        lock.unlock()
        t.resume()
    }

    public func reattach(to destination: URL, delegate: any KokoroDownloadDelegate) async -> Bool {
        let session = makeSession()
        let tasks = await session.allTasks
        guard
            let running = tasks.compactMap({ $0 as? URLSessionDownloadTask }).first(where: {
                $0.state == .running
            })
        else {
            return false
        }
        lock.withLock {
            self.destination = destination
            self.delegate = delegate
            task = running
        }
        return true
    }

    public func cancel() {
        lock.lock()
        let t = task
        task = nil
        lock.unlock()
        t?.cancel()
    }

    private func current() -> (URL?, (any KokoroDownloadDelegate)?) {
        lock.lock()
        defer { lock.unlock() }
        return (destination, delegate)
    }

    public func urlSession(
        _ session: URLSession, downloadTask: URLSessionDownloadTask, didWriteData bytesWritten: Int64,
        totalBytesWritten: Int64, totalBytesExpectedToWrite: Int64
    ) {
        guard totalBytesExpectedToWrite > 0 else { return }
        let fraction = Double(totalBytesWritten) / Double(totalBytesExpectedToWrite)
        let (_, delegate) = current()
        Task { @MainActor in delegate?.downloadProgressed(min(max(fraction, 0), 1)) }
    }

    public func urlSession(
        _ session: URLSession, downloadTask: URLSessionDownloadTask, didFinishDownloadingTo location: URL
    ) {
        let (destination, delegate) = current()
        guard let destination else { return }
        // The temporary file is gone once this returns, so the move happens here.
        let moved: Result<Void, Error> = Result {
            if let http = downloadTask.response as? HTTPURLResponse, http.statusCode != 200 {
                throw URLError(.badServerResponse, userInfo: ["status": http.statusCode])
            }
            try? FileManager.default.removeItem(at: destination)
            try FileManager.default.createDirectory(
                at: destination.deletingLastPathComponent(), withIntermediateDirectories: true)
            try FileManager.default.moveItem(at: location, to: destination)
        }
        Task { @MainActor in
            switch moved {
            case .success: delegate?.downloadFinished()
            case .failure(let error):
                delegate?.downloadFailed(Self.failure(for: error, task: downloadTask), resumeData: nil)
            }
        }
    }

    public func urlSession(_ session: URLSession, task: URLSessionTask, didCompleteWithError error: Error?) {
        guard let error else { return }
        let ns = error as NSError
        // A cancel from the store is the store's own doing and is not reported back.
        if ns.domain == NSURLErrorDomain && ns.code == NSURLErrorCancelled { return }
        let resume = ns.userInfo[NSURLSessionDownloadTaskResumeData] as? Data
        let (_, delegate) = current()
        let failure = Self.failure(for: error, task: task)
        Task { @MainActor in delegate?.downloadFailed(failure, resumeData: resume) }
    }

    static func failure(for error: Error, task: URLSessionTask) -> KokoroDownloadFailure {
        let ns = error as NSError
        if ns.domain == NSURLErrorDomain,
            [
                NSURLErrorNotConnectedToInternet, NSURLErrorNetworkConnectionLost, NSURLErrorCannotFindHost,
                NSURLErrorCannotConnectToHost, NSURLErrorDNSLookupFailed, NSURLErrorTimedOut,
            ].contains(ns.code)
        {
            return .offline
        }
        if let http = task.response as? HTTPURLResponse, http.statusCode != 200 {
            return .http(http.statusCode)
        }
        if let status = ns.userInfo["status"] as? Int { return .http(status) }
        return .other(error.localizedDescription)
    }
}

/// `KokoroDownloading` requires `Sendable`; every mutable field is guarded by `lock`.
extension URLSessionKokoroDownloader: @unchecked Sendable {}
