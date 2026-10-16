import Foundation

public struct PlannedPath: Hashable, Sendable {
    public let url: URL
    public let bytes: Int64
}

/// A shared blob that stays on disk because a model that is *not* being removed still uses it.
public struct KeptBlob: Hashable, Sendable {
    public let digest: String
    public let bytes: Int64
    public let stillUsedBy: [String]
}

/// Exactly what a removal would do. Shown to the user before anything is touched.
public struct RemovalPlan: Hashable, Sendable {
    public let entries: [ModelEntry]
    /// Manifests/folders first, shared blobs last, so an interrupted run leaves orphaned
    /// blobs (harmless) rather than a model entry pointing at missing data (broken).
    public let paths: [PlannedPath]
    public let reclaimableBytes: Int64
    public let keptBlobs: [KeptBlob]

    public var isEmpty: Bool { entries.isEmpty }
    public var keptBytes: Int64 { keptBlobs.reduce(Int64(0)) { $0 + $1.bytes } }
}

public enum RemovalPlanner {
    public static func plan(removing selected: [ModelEntry], from all: [ModelEntry]) -> RemovalPlan {
        let selectedIDs = Set(selected.map { $0.id })

        var paths: [PlannedPath] = []
        var reclaimable: Int64 = 0

        // Exclusive paths (manifests, whole cache folders, GGUF files + sidecars).
        for entry in selected {
            let count = max(entry.exclusivePaths.count, 1)
            let perPath = entry.exclusiveBytes / Int64(count)
            for url in entry.exclusivePaths {
                paths.append(PlannedPath(url: url, bytes: perPath))
            }
            reclaimable += entry.exclusiveBytes
        }

        // Which entries reference each blob digest.
        var usersByDigest: [String: [ModelEntry]] = [:]
        for entry in all {
            for blob in entry.blobs {
                usersByDigest[blob.digest, default: []].append(entry)
            }
        }

        var handled = Set<String>()
        var kept: [KeptBlob] = []
        for entry in selected {
            for blob in entry.blobs where handled.insert(blob.digest).inserted {
                let users = usersByDigest[blob.digest] ?? []
                let survivors = users.filter { !selectedIDs.contains($0.id) }
                if survivors.isEmpty {
                    paths.append(PlannedPath(url: blob.url, bytes: blob.size))
                    reclaimable += blob.size
                } else {
                    kept.append(KeptBlob(digest: blob.digest, bytes: blob.size, stillUsedBy: survivors.map { $0.name }.sorted()))
                }
            }
        }

        return RemovalPlan(
            entries: selected,
            paths: paths,
            reclaimableBytes: reclaimable,
            keptBlobs: kept.sorted { $0.bytes > $1.bytes }
        )
    }
}
