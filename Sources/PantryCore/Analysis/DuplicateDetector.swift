import Foundation

public struct DuplicateGroup: Identifiable, Hashable, Sendable {
    public enum Kind: String, Sendable {
        /// Byte-for-byte identical weights files stored in more than one place.
        case identical
        /// Same model family and size, different build (quantization, format or runtime).
        case similar
    }

    public let id: String
    public let kind: Kind
    public let entries: [ModelEntry]
    /// For identical groups: bytes that would be freed by keeping only one copy. Nil for similar groups.
    public let reclaimableBytes: Int64?

    public var totalBytes: Int64 { StorageSummary.physicalBytes(of: entries) }
}

public struct DuplicateDetector {
    public typealias Hasher = @Sendable (URL) throws -> String
    private let hasher: Hasher

    public init(hasher: @escaping Hasher = { try FileHasher.sha256Hex(of: $0) }) {
        self.hasher = hasher
    }

    // MARK: Identical files

    private struct Candidate {
        let entryID: String
        let file: ModelFile
        let physicalPath: String
    }

    /// Finds weights files with the same content in different physical locations.
    /// Only files that share a size with another file are ever read, so unique models cost nothing.
    public func findIdentical(in entries: [ModelEntry]) -> [DuplicateGroup] {
        var bySize: [Int64: [Candidate]] = [:]
        for entry in entries {
            for file in entry.files {
                let physical = file.url.resolvingSymlinksInPath().standardizedFileURL.path
                bySize[file.size, default: []].append(Candidate(entryID: entry.id, file: file, physicalPath: physical))
            }
        }

        let entriesByID = Dictionary(entries.map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })
        var groups: [DuplicateGroup] = []

        for (size, candidates) in bySize {
            // A size that only one physical file has can never be a duplicate.
            guard Set(candidates.map { $0.physicalPath }).count > 1 else { continue }

            // Hash every physical file once, even if two entries reference it.
            var hashByPath: [String: String] = [:]
            for candidate in candidates where hashByPath[candidate.physicalPath] == nil {
                if let known = candidate.file.knownSHA256 {
                    hashByPath[candidate.physicalPath] = known
                } else if let computed = try? hasher(candidate.file.url) {
                    hashByPath[candidate.physicalPath] = computed
                }
            }

            var byHash: [String: [Candidate]] = [:]
            for candidate in candidates {
                if let digest = hashByPath[candidate.physicalPath] {
                    byHash[digest, default: []].append(candidate)
                }
            }

            for (digest, members) in byHash {
                let paths = Set(members.map { $0.physicalPath })
                guard paths.count > 1 else { continue }
                var seen = Set<String>()
                let groupEntries = members
                    .compactMap { entriesByID[$0.entryID] }
                    .filter { seen.insert($0.id).inserted }
                guard groupEntries.count > 1 else { continue }
                groups.append(DuplicateGroup(
                    id: "identical:" + String(digest.prefix(16)),
                    kind: .identical,
                    entries: groupEntries.sorted { $0.name < $1.name },
                    reclaimableBytes: size * Int64(paths.count - 1)
                ))
            }
        }
        return groups.sorted { ($0.reclaimableBytes ?? 0) > ($1.reclaimableBytes ?? 0) }
    }

    // MARK: Similar models

    private struct Parsed {
        let entry: ModelEntry
        let name: ParsedModelName
        let billions: Double?
    }

    private static func isCompatible(_ a: Parsed, _ b: Parsed) -> Bool {
        guard let x = a.billions, let y = b.billions, ParameterSize.areClose(x, y) else { return false }
        if let ia = a.name.isInstruct, let ib = b.name.isInstruct, ia != ib { return false }
        return true
    }

    /// Groups models that are probably the same network in different packaging
    /// ("llama3.2:3b" in Ollama and "Llama-3.2-3B-Instruct-4bit" in MLX).
    /// Groups already explained by an identical-file group are left out.
    public static func findSimilar(in entries: [ModelEntry], excluding identical: [DuplicateGroup] = []) -> [DuplicateGroup] {
        var parsed: [Parsed] = []
        for entry in entries {
            let name = ModelNameParser.parse(entry.name)
            guard name.baseKey.count >= 3 else { continue }
            let billions = entry.parameterSize.flatMap { ParameterSize.billions(from: $0) } ?? name.parameterBillions
            parsed.append(Parsed(entry: entry, name: name, billions: billions))
        }

        var buckets: [String: [Parsed]] = [:]
        for item in parsed { buckets[item.name.baseKey, default: []].append(item) }

        let identicalSets: [Set<String>] = identical.map { Set($0.entries.map { $0.id }) }
        var groups: [DuplicateGroup] = []

        for (key, bucket) in buckets where bucket.count > 1 {
            // Union-find over compatible pairs, so A~B and B~C puts all three together.
            var parent = Array(0..<bucket.count)
            func find(_ index: Int) -> Int {
                var root = index
                while parent[root] != root { root = parent[root] }
                var node = index
                while parent[node] != root {
                    let next = parent[node]
                    parent[node] = root
                    node = next
                }
                return root
            }
            for i in 0..<bucket.count {
                var j = i + 1
                while j < bucket.count {
                    if isCompatible(bucket[i], bucket[j]) {
                        let a = find(i)
                        let b = find(j)
                        if a != b { parent[a] = b }
                    }
                    j += 1
                }
            }
            var components: [Int: [Parsed]] = [:]
            for i in 0..<bucket.count { components[find(i), default: []].append(bucket[i]) }

            for (_, members) in components where members.count > 1 {
                let ids = Set(members.map { $0.entry.id })
                if identicalSets.contains(where: { ids.isSubset(of: $0) }) { continue }
                let sorted = members.map { $0.entry }.sorted { $0.sizeBytes > $1.sizeBytes }
                // Deterministic id: stable across rescans so UI selection survives a refresh.
                let signature = sorted.map { $0.id }.sorted().joined(separator: "|")
                groups.append(DuplicateGroup(
                    id: "similar:" + key + ":" + signature,
                    kind: .similar,
                    entries: sorted,
                    reclaimableBytes: nil
                ))
            }
        }
        return groups.sorted { $0.totalBytes > $1.totalBytes }
    }
}
