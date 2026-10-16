import Foundation

public enum DiskSpace {
    /// Space the system would let an app use right now (includes purgeable space).
    public static func availableBytes(at url: URL) -> Int64? {
        let values = try? url.resourceValues(forKeys: [.volumeAvailableCapacityForImportantUsageKey])
        return values?.volumeAvailableCapacityForImportantUsage
    }

    public static func totalBytes(at url: URL) -> Int64? {
        let values = try? url.resourceValues(forKeys: [.volumeTotalCapacityKey])
        return values?.volumeTotalCapacity.map { Int64($0) }
    }
}
