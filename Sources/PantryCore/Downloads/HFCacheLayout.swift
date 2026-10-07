import Foundation

/// Writes the same on-disk layout `huggingface_hub` uses, so downloads made by Pantry are
/// picked up by `mlx-lm`, `transformers`, and the `hf` CLI (and the other way round):
///
///     models--org--name/
///       blobs/<etag>
///       refs/main                      (commit sha)
///       snapshots/<sha>/<path>  ->  ../../blobs/<etag>   (relative symlink)
public struct HFCacheLayout: Sendable {
    public let hubRoot: URL

    public init(hubRoot: URL) {
        self.hubRoot = hubRoot
    }

    public func repoDir(for repo: String) -> URL {
        hubRoot.appendingPathComponent("models--" + repo.replacingOccurrences(of: "/", with: "--"), isDirectory: true)
    }

    public func blobsDir(for repo: String) -> URL {
        repoDir(for: repo).appendingPathComponent("blobs", isDirectory: true)
    }

    public func blobURL(repo: String, etag: String) -> URL {
        blobsDir(for: repo).appendingPathComponent(etag)
    }

    public func snapshotURL(repo: String, revision: String) -> URL {
        repoDir(for: repo).appendingPathComponent("snapshots", isDirectory: true).appendingPathComponent(revision, isDirectory: true)
    }

    /// Relative target from a snapshot file back to its blob: `../../blobs/<etag>` for a
    /// top-level file, one extra `../` per sub-folder.
    public static func relativeBlobTarget(forFilePath path: String, etag: String) -> String {
        let depth = path.split(separator: "/").count
        return String(repeating: "../", count: depth + 1) + "blobs/" + etag
    }

    /// Creates the snapshot symlinks and `refs/main`. Safe to call again (existing links are replaced).
    public func commit(repo: String, revision: String, files: [(path: String, etag: String)]) throws {
        let fm = FileManager.default
        let snapshot = snapshotURL(repo: repo, revision: revision)
        for file in files {
            let link = snapshot.appendingPathComponent(file.path)
            try fm.createDirectory(at: link.deletingLastPathComponent(), withIntermediateDirectories: true)
            if (try? fm.destinationOfSymbolicLink(atPath: link.path)) != nil || fm.fileExists(atPath: link.path) {
                try fm.removeItem(at: link)
            }
            try fm.createSymbolicLink(atPath: link.path, withDestinationPath: Self.relativeBlobTarget(forFilePath: file.path, etag: file.etag))
        }
        let refs = repoDir(for: repo).appendingPathComponent("refs", isDirectory: true)
        try fm.createDirectory(at: refs, withIntermediateDirectories: true)
        try revision.write(to: refs.appendingPathComponent("main"), atomically: true, encoding: .utf8)
    }
}
