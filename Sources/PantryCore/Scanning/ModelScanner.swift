import Foundation

/// A scanner reads one on-disk model store and reports what is in it. Scanners are
/// read-only and synchronous; `ModelLibrary` runs them concurrently off the main thread.
public protocol ModelScanner: Sendable {
    /// Human-readable source, used in warnings ("Ollama", "~/models").
    var label: String { get }
    func scan() throws -> [ModelEntry]
}

/// Files at or above this size are candidates for exact-duplicate detection.
public let defaultDuplicateCandidateBytes: Int64 = 50_000_000
