import Foundation

enum FileSizing {
    /// Size of a regular file. Symlinks and directories return nil (symlinks are never followed).
    static func regularFileSize(at url: URL, fileManager: FileManager = .default) -> Int64? {
        guard let attrs = try? fileManager.attributesOfItem(atPath: url.path) else { return nil }
        guard let type = attrs[.type] as? FileAttributeType, type == .typeRegular else { return nil }
        return (attrs[.size] as? NSNumber)?.int64Value
    }

    /// Sum of all regular files below `url`. Symlinks are skipped so shared storage is not double counted.
    static func directorySize(at url: URL, fileManager: FileManager = .default) -> Int64 {
        let keys: [URLResourceKey] = [.isRegularFileKey, .fileSizeKey, .isSymbolicLinkKey]
        guard let enumerator = fileManager.enumerator(at: url, includingPropertiesForKeys: keys, options: []) else {
            return 0
        }
        var total: Int64 = 0
        for case let item as URL in enumerator {
            guard let values = try? item.resourceValues(forKeys: Set(keys)) else { continue }
            if values.isSymbolicLink == true { continue }
            if values.isRegularFile == true {
                total += Int64(values.fileSize ?? 0)
            }
        }
        return total
    }

    static func modificationDate(at url: URL) -> Date? {
        (try? url.resourceValues(forKeys: [.contentModificationDateKey]))?.contentModificationDate
    }
}
