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

    /// Space-saving size for the menu bar: whole numbers, always rounded up ("177.77 GB" -> "178 GB").
    /// Decimal units like `string(_:)`. A round-up that reaches 1000 moves to the next unit.
    public static func compact(_ bytes: Int64) -> String {
        let units = ["bytes", "KB", "MB", "GB", "TB"]
        var value = Double(max(bytes, 0))
        var index = 0
        while index < units.count - 1, value.rounded(.up) >= 1000 {
            value /= 1000
            index += 1
        }
        let whole = Int(value.rounded(.up))
        if index > 0, whole >= 1000, index < units.count - 1 { return "1 \(units[index + 1])" }
        return "\(whole) \(units[index])"
    }
}
