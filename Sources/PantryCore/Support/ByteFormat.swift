import Foundation

public enum ByteFormat {
    /// Finder-style decimal sizes ("4.7 GB"), so numbers match what users see elsewhere.
    public static func string(_ bytes: Int64) -> String {
        let formatter = ByteCountFormatter()
        formatter.countStyle = .file
        formatter.allowedUnits = [.useMB, .useGB, .useTB, .useKB, .useBytes]
        formatter.includesUnit = true
        return formatter.string(fromByteCount: bytes)
    }
}
