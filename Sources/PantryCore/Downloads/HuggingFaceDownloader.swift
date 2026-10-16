import Foundation

public struct HuggingFaceDownloader: Sendable {
    public let client: HuggingFaceClient
    public let layout: HFCacheLayout

    public init(client: HuggingFaceClient, layout: HFCacheLayout) {
        self.client = client
        self.layout = layout
    }

    /// Downloads every file of a repo into the shared Hugging Face cache layout.
    /// Files that are already in the cache are skipped, so a cancelled download resumes
    /// at file granularity the next time.
    public func downloadRepo(_ details: HFRepoDetails, onProgress: @escaping @Sendable (DownloadProgress) -> Void) async throws {
        let fm = FileManager.default
        let repo = details.id
        let total = details.totalBytes
        try fm.createDirectory(at: layout.blobsDir(for: repo), withIntermediateDirectories: true)

        var completedBefore: Int64 = 0
        var committed: [(path: String, etag: String)] = []
        onProgress(DownloadProgress(phase: "Starting", completedBytes: 0, totalBytes: total))

        for file in details.files {
            try Task.checkCancellation()
            let blob = layout.blobURL(repo: repo, etag: file.etag)
            if !fm.fileExists(atPath: blob.path) {
                let base = completedBefore
                let downloader = FileDownloader(destination: blob) { written in
                    onProgress(DownloadProgress(phase: "Downloading", completedBytes: base + written, totalBytes: total))
                }
                let url = client.resolveURL(repo: repo, revision: details.revision, path: file.path)
                try await downloader.download(client.authorizedRequest(url))
            }
            completedBefore += file.size
            committed.append((file.path, file.etag))
            onProgress(DownloadProgress(phase: "Downloading", completedBytes: completedBefore, totalBytes: total))
        }

        onProgress(DownloadProgress(phase: "Finishing up", completedBytes: total, totalBytes: total))
        try layout.commit(repo: repo, revision: details.revision, files: committed)
        onProgress(DownloadProgress(phase: "Done", completedBytes: total, totalBytes: total))
    }

    /// Downloads one file (typically a single GGUF quantization) into a plain folder, the way
    /// llama.cpp's own `-hf` cache names it: `<org>_<repo>_<file>`.
    public func downloadSingleFile(
        repo: String,
        revision: String,
        file: HFRepoFile,
        into folder: URL,
        onProgress: @escaping @Sendable (DownloadProgress) -> Void
    ) async throws -> URL {
        let flatName = repo.replacingOccurrences(of: "/", with: "_") + "_" + file.path.replacingOccurrences(of: "/", with: "_")
        let destination = folder.appendingPathComponent(flatName)
        let total = file.size
        onProgress(DownloadProgress(phase: "Starting", completedBytes: 0, totalBytes: total))
        let downloader = FileDownloader(destination: destination) { written in
            onProgress(DownloadProgress(phase: "Downloading", completedBytes: written, totalBytes: total))
        }
        let url = client.resolveURL(repo: repo, revision: revision, path: file.path)
        try await downloader.download(client.authorizedRequest(url))
        onProgress(DownloadProgress(phase: "Done", completedBytes: total, totalBytes: total))
        return destination
    }
}
