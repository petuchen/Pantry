import Foundation

public enum PathSafety {
    /// True when `child` lives strictly below `root` (never equal to it), judged after
    /// resolving symlinks in the *parent* directory. A symlinked parent that points outside
    /// the root is therefore rejected, while `child` itself may be a symlink (we remove the
    /// link, never its target).
    public static func isStrictlyInside(_ child: URL, root: URL) -> Bool {
        let rootComponents = root.resolvingSymlinksInPath().standardizedFileURL.pathComponents
        let std = child.standardizedFileURL
        let parentComponents = std.deletingLastPathComponent().resolvingSymlinksInPath().standardizedFileURL.pathComponents
        let childComponents = parentComponents + [std.lastPathComponent]
        guard childComponents.count > rootComponents.count else { return false }
        return Array(childComponents.prefix(rootComponents.count)) == rootComponents
    }

    /// Path components of `url` below `root`, or nil if it is not below it.
    /// Tries the literal form first, then a form where only the *parent directory* is
    /// symlink-resolved (macOS `/var` vs `/private/var`). The final component is never
    /// resolved, so symlinked files (Hugging Face snapshots) keep their own names.
    public static func relativeComponents(of url: URL, under root: URL) -> [String]? {
        let resolvedParent = url.deletingLastPathComponent().resolvingSymlinksInPath()
            .appendingPathComponent(url.lastPathComponent)
        let pairs: [(URL, URL)] = [
            (url, root),
            (resolvedParent, root.resolvingSymlinksInPath()),
        ]
        for (candidate, base) in pairs {
            let c = candidate.standardizedFileURL.pathComponents
            let b = base.standardizedFileURL.pathComponents
            if c.count > b.count && Array(c.prefix(b.count)) == b {
                return Array(c.dropFirst(b.count))
            }
        }
        return nil
    }
}
