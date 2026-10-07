import Foundation

/// Downloads one URL to one destination with byte progress and cancellation.
/// The file is written to a temporary location by URLSession and moved into place only
/// when it completed successfully, so a cancelled download never leaves a half-written file.
final class FileDownloader: NSObject, URLSessionDownloadDelegate, @unchecked Sendable {
    private let destination: URL
    private let onBytes: @Sendable (Int64) -> Void
    private var session: URLSession!
    private var task: URLSessionDownloadTask?
    private var continuation: CheckedContinuation<Void, Error>?
    private var failure: Error?

    init(destination: URL, onBytes: @escaping @Sendable (Int64) -> Void) {
        self.destination = destination
        self.onBytes = onBytes
        super.init()
        self.session = URLSession(configuration: .default, delegate: self, delegateQueue: nil)
    }

    func download(_ request: URLRequest) async throws {
        try await withTaskCancellationHandler {
            try await withCheckedThrowingContinuation { (cont: CheckedContinuation<Void, Error>) in
                self.continuation = cont
                let downloadTask = self.session.downloadTask(with: request)
                self.task = downloadTask
                downloadTask.resume()
                if Task.isCancelled { downloadTask.cancel() }
            }
        } onCancel: {
            self.task?.cancel()
        }
    }

    func urlSession(_ session: URLSession, downloadTask: URLSessionDownloadTask, didWriteData bytesWritten: Int64, totalBytesWritten: Int64, totalBytesExpectedToWrite: Int64) {
        onBytes(totalBytesWritten)
    }

    func urlSession(_ session: URLSession, downloadTask: URLSessionDownloadTask, didFinishDownloadingTo location: URL) {
        if let http = downloadTask.response as? HTTPURLResponse, !(200..<300).contains(http.statusCode) {
            switch http.statusCode {
            case 401, 403: failure = DownloadError.needsAuthentication
            case 404: failure = DownloadError.notFound
            default: failure = DownloadError.http(http.statusCode)
            }
            return
        }
        let fm = FileManager.default
        do {
            try fm.createDirectory(at: destination.deletingLastPathComponent(), withIntermediateDirectories: true)
            if fm.fileExists(atPath: destination.path) { try fm.removeItem(at: destination) }
            try fm.moveItem(at: location, to: destination)
        } catch {
            failure = error
        }
    }

    func urlSession(_ session: URLSession, task: URLSessionTask, didCompleteWithError error: Error?) {
        session.finishTasksAndInvalidate()
        let cont = continuation
        continuation = nil
        if let error {
            if (error as? URLError)?.code == .cancelled {
                cont?.resume(throwing: CancellationError())
            } else {
                cont?.resume(throwing: failure ?? error)
            }
        } else if let failure {
            cont?.resume(throwing: failure)
        } else {
            cont?.resume()
        }
    }
}
