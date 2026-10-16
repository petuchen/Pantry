import Foundation

public struct ServiceUsage: Identifiable, Hashable, Sendable {
    public let service: ModelService
    public let bytes: Int64
    public let modelCount: Int
    public var id: String { service.rawValue }
}

public struct CategoryUsage: Identifiable, Hashable, Sendable {
    public let category: ModelCategory
    public let bytes: Int64
    public let modelCount: Int
    public var id: String { category.rawValue }
}

public struct StorageSummary: Sendable {
    /// Bytes physically on disk. Shared Ollama layers are counted once, so this can be
    /// smaller than the sum of the models' individual sizes.
    public let totalBytes: Int64
    public let modelCount: Int
    /// Services with at least one model, largest first.
    public let byService: [ServiceUsage]
    public let byCategory: [CategoryUsage]
    public let largest: [ModelEntry]
    public let incompleteCount: Int

    public static let empty = StorageSummary(totalBytes: 0, modelCount: 0, byService: [], byCategory: [], largest: [], incompleteCount: 0)

    public static func make(from entries: [ModelEntry], largestCount: Int = 5) -> StorageSummary {
        let byService: [ServiceUsage] = ModelService.allCases.compactMap { service in
            let subset = entries.filter { $0.service == service }
            guard !subset.isEmpty else { return nil }
            return ServiceUsage(service: service, bytes: physicalBytes(of: subset), modelCount: subset.count)
        }.sorted { $0.bytes > $1.bytes }

        let byCategory: [CategoryUsage] = ModelCategory.allCases.compactMap { category in
            let subset = entries.filter { $0.category == category }
            guard !subset.isEmpty else { return nil }
            return CategoryUsage(category: category, bytes: physicalBytes(of: subset), modelCount: subset.count)
        }.sorted { $0.bytes > $1.bytes }

        return StorageSummary(
            totalBytes: byService.reduce(Int64(0)) { $0 + $1.bytes },
            modelCount: entries.count,
            byService: byService,
            byCategory: byCategory,
            largest: Array(entries.sorted { $0.sizeBytes > $1.sizeBytes }.prefix(largestCount)),
            incompleteCount: entries.filter { $0.isIncomplete }.count
        )
    }

    /// Exclusive bytes plus each distinct shared blob once.
    public static func physicalBytes(of entries: [ModelEntry]) -> Int64 {
        var total: Int64 = 0
        var seenDigests = Set<String>()
        for entry in entries {
            total += entry.exclusiveBytes
            for blob in entry.blobs where seenDigests.insert(blob.digest).inserted {
                total += blob.size
            }
        }
        return total
    }
}
