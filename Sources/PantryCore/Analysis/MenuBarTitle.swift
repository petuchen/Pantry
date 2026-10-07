import Foundation

/// Decides the short text shown next to the menu bar icon. Kept in the core library so the
/// rules are unit tested: the menu bar is the most space-constrained surface in the app.
public enum MenuBarTitle {
    /// - Returns: nil when only the icon should be shown.
    ///
    /// Priority: an active download's progress wins over the size, because that is what changes
    /// while the user is watching. The size is hidden until the first scan finishes so the bar
    /// never flashes "0 bytes" on launch.
    public static func text(
        hasScanned: Bool,
        showSize: Bool,
        totalBytes: Int64,
        runningDownloads: Int,
        downloadFraction: Double?
    ) -> String? {
        if runningDownloads > 0 {
            guard let fraction = downloadFraction else { return nil }
            let percent = Int((min(max(fraction, 0), 1) * 100).rounded())
            return "\(percent)%"
        }
        guard showSize, hasScanned else { return nil }
        return ByteFormat.compact(totalBytes)
    }

    /// SF Symbol for the menu bar: a download arrow while something is downloading.
    public static func symbolName(runningDownloads: Int) -> String {
        runningDownloads > 0 ? "arrow.down.circle" : "shippingbox"
    }

    /// Spoken description of the menu bar item (the visible text is deliberately terse).
    public static func accessibilityLabel(
        hasScanned: Bool,
        totalBytes: Int64,
        runningDownloads: Int,
        downloadFraction: Double?
    ) -> String {
        if runningDownloads > 0 {
            let count = runningDownloads == 1 ? "1 download" : "\(runningDownloads) downloads"
            if let fraction = downloadFraction {
                return "Pantry, \(count) in progress, \(Int((min(max(fraction, 0), 1) * 100).rounded())) percent"
            }
            return "Pantry, \(count) in progress"
        }
        guard hasScanned else { return "Pantry, scanning models" }
        return "Pantry, models use \(ByteFormat.string(totalBytes))"
    }
}
