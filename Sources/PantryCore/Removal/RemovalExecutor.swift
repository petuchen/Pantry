import Foundation

public enum RemovalMode: String, Sendable {
    /// Recoverable: items go to the Trash. Disk space is only freed once the Trash is emptied.
    case moveToTrash
    /// Immediate and not recoverable.
    case deletePermanently
}

public struct RemovalFailure: Hashable, Sendable {
    public let path: String
    public let message: String
}

public struct RemovalResult: Sendable {
    public let mode: RemovalMode
    public let removedPaths: [String]
    public let failures: [RemovalFailure]
    public let bytesRemoved: Int64

    public var isCompleteSuccess: Bool { failures.isEmpty }
}

/// Performs a `RemovalPlan`, but only inside folders Pantry knows about.
public struct RemovalExecutor {
    public let allowedRoots: [URL]

    public init(allowedRoots: [URL]) {
        self.allowedRoots = allowedRoots
    }

    public func execute(_ plan: RemovalPlan, mode: RemovalMode) -> RemovalResult {
        let fm = FileManager.default

        // All-or-nothing safety check first: if any path is outside the known folders,
        // nothing is touched at all.
        let unsafe = plan.paths.filter { planned in
            !allowedRoots.contains { PathSafety.isStrictlyInside(planned.url, root: $0) }
        }
        if !unsafe.isEmpty {
            let failures = unsafe.map {
                RemovalFailure(path: $0.url.path, message: "This item is outside the folders Pantry manages, so it was left alone.")
            }
            return RemovalResult(mode: mode, removedPaths: [], failures: failures, bytesRemoved: 0)
        }

        var removed: [String] = []
        var failures: [RemovalFailure] = []
        var bytes: Int64 = 0

        for planned in plan.paths {
            let url = planned.url
            // `fileExists` follows symlinks; check the link itself too so dangling links are removed.
            let exists = fm.fileExists(atPath: url.path) || (try? fm.destinationOfSymbolicLink(atPath: url.path)) != nil
            guard exists else { continue }
            do {
                switch mode {
                case .moveToTrash:
                    try fm.trashItem(at: url, resultingItemURL: nil)
                case .deletePermanently:
                    try fm.removeItem(at: url)
                }
                removed.append(url.path)
                bytes += planned.bytes
                pruneEmptyManifestFolders(above: url)
            } catch {
                failures.append(RemovalFailure(path: url.path, message: error.localizedDescription))
            }
        }
        return RemovalResult(mode: mode, removedPaths: removed, failures: failures, bytesRemoved: bytes)
    }

    /// Ollama keeps manifests at manifests/<host>/<namespace>/<name>/<tag>. After removing the
    /// last tag, delete the now-empty <name>, <namespace> and <host> folders, never `manifests` itself.
    private func pruneEmptyManifestFolders(above removed: URL) {
        let fm = FileManager.default
        guard removed.pathComponents.contains("manifests") else { return }
        var folder = removed.deletingLastPathComponent()
        while folder.lastPathComponent != "manifests" && folder.pathComponents.count > 1 {
            let contents = (try? fm.contentsOfDirectory(atPath: folder.path)) ?? ["-"]
            let meaningful = contents.filter { $0 != ".DS_Store" }
            guard meaningful.isEmpty else { return }
            guard allowedRoots.contains(where: { PathSafety.isStrictlyInside(folder, root: $0) }) else { return }
            try? fm.removeItem(at: folder)
            folder = folder.deletingLastPathComponent()
        }
    }
}
