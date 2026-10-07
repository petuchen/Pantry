import Foundation

/// Scans an ordinary folder tree for `.gguf` files (llama.cpp's cache, ~/models, LM Studio…)
/// and for plain safetensors model directories (a `config.json` next to `*.safetensors`,
/// or a diffusers `model_index.json`).
public struct LooseFolderScanner: ModelScanner {
    public let root: URL
    public let service: ModelService
    public let minimumCandidateBytes: Int64
    public let maxDepth: Int
    public var label: String { root.path }

    public init(
        root: URL,
        service: ModelService,
        minimumCandidateBytes: Int64 = defaultDuplicateCandidateBytes,
        maxDepth: Int = 6
    ) {
        self.root = root
        self.service = service
        self.minimumCandidateBytes = minimumCandidateBytes
        self.maxDepth = maxDepth
    }

    public func scan() throws -> [ModelEntry] {
        guard FileManager.default.fileExists(atPath: root.path) else { return [] }
        var entries: [ModelEntry] = []
        var ggufFiles: [URL] = []
        walk(root, depth: 0, entries: &entries, ggufFiles: &ggufFiles)
        entries.append(contentsOf: makeGGUFEntries(ggufFiles))
        return entries
    }

    private func walk(_ dir: URL, depth: Int, entries: inout [ModelEntry], ggufFiles: inout [URL]) {
        let fm = FileManager.default
        guard let children = try? fm.contentsOfDirectory(
            at: dir,
            includingPropertiesForKeys: [.isDirectoryKey, .isSymbolicLinkKey, .isRegularFileKey],
            options: [.skipsHiddenFiles]
        ) else { return }

        let names = Set(children.map { $0.lastPathComponent.lowercased() })
        let hasSafetensors = names.contains { $0.hasSuffix(".safetensors") }
        if (names.contains("config.json") && hasSafetensors) || names.contains("model_index.json") {
            if let entry = makeDirectoryEntry(dir, isDiffusers: names.contains("model_index.json")) {
                entries.append(entry)
            }
            return
        }

        for child in children {
            let values = try? child.resourceValues(forKeys: [.isDirectoryKey, .isSymbolicLinkKey, .isRegularFileKey])
            if values?.isSymbolicLink == true { continue }
            if values?.isDirectory == true {
                if depth < maxDepth { walk(child, depth: depth + 1, entries: &entries, ggufFiles: &ggufFiles) }
            } else if values?.isRegularFile == true, child.pathExtension.lowercased() == "gguf" {
                ggufFiles.append(child)
            }
        }
    }

    private func relativeName(for url: URL) -> String {
        PathSafety.relativeComponents(of: url, under: root)?.joined(separator: "/") ?? url.lastPathComponent
    }

    private func makeDirectoryEntry(_ dir: URL, isDiffusers: Bool) -> ModelEntry? {
        let size = FileSizing.directorySize(at: dir)
        guard size > 0 else { return nil }
        let name = relativeName(for: dir)
        var architectures: [String] = []
        if let data = try? Data(contentsOf: dir.appendingPathComponent("config.json")),
           let json = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any] {
            architectures = (json["architectures"] as? [String]) ?? []
        }
        var files: [ModelFile] = []
        if let names = try? FileManager.default.contentsOfDirectory(atPath: dir.path) {
            for fileName in names where fileName.lowercased().hasSuffix(".safetensors") {
                let url = dir.appendingPathComponent(fileName)
                if let fileSize = FileSizing.regularFileSize(at: url), fileSize >= minimumCandidateBytes {
                    files.append(ModelFile(url: url, size: fileSize))
                }
            }
        }
        let parsed = ModelNameParser.parse(name)
        return ModelEntry(
            id: "\(service.rawValue):" + name,
            service: service,
            name: name,
            sizeBytes: size,
            revealURL: dir,
            format: isDiffusers ? .diffusers : .safetensors,
            category: ModelClassifier.classify(name: name, hints: ClassificationHints(architectures: architectures, isDiffusers: isDiffusers)),
            parameterSize: parsed.parameterLabel,
            quantization: parsed.quantization,
            modifiedAt: FileSizing.modificationDate(at: dir),
            exclusivePaths: [dir],
            exclusiveBytes: size,
            files: files
        )
    }

    /// llama.cpp's download cache names files `<org>_<repo>-GGUF_<file>.gguf`. Show just the file part.
    static func cleanGGUFName(_ fileName: String) -> String {
        guard let range = fileName.range(of: "-gguf_", options: .caseInsensitive) else { return fileName }
        let remainder = String(fileName[range.upperBound...])
        return remainder.isEmpty ? fileName : remainder
    }

    private static let shardRegex = try! NSRegularExpression(pattern: #"^(.*)-(\d{5})-of-(\d{5})\.gguf$"#, options: [.caseInsensitive])

    private func makeGGUFEntries(_ urls: [URL]) -> [ModelEntry] {
        // Group "model-00001-of-00003.gguf" shards into one model.
        var groups: [String: [URL]] = [:]
        var order: [String] = []
        for url in urls {
            let file = url.lastPathComponent
            let ns = file as NSString
            var key = url.deletingPathExtension().path
            if let match = Self.shardRegex.firstMatch(in: file, options: [], range: NSRange(location: 0, length: ns.length)) {
                let base = ns.substring(with: match.range(at: 1))
                key = url.deletingLastPathComponent().appendingPathComponent(base).path
            }
            if groups[key] == nil { order.append(key) }
            groups[key, default: []].append(url)
        }

        var entries: [ModelEntry] = []
        for key in order {
            guard let shards = groups[key]?.sorted(by: { $0.lastPathComponent < $1.lastPathComponent }), let first = shards.first else { continue }
            var total: Int64 = 0
            var files: [ModelFile] = []
            var paths: [URL] = []
            var exclusive: Int64 = 0
            for shard in shards {
                let size = FileSizing.regularFileSize(at: shard) ?? 0
                total += size
                if size >= minimumCandidateBytes { files.append(ModelFile(url: shard, size: size)) }
                paths.append(shard)
                exclusive += size
                // llama.cpp's download cache keeps `<file>.json` / `<file>.etag` metadata beside each file.
                for suffix in [".json", ".etag"] {
                    let sidecar = URL(fileURLWithPath: shard.path + suffix)
                    if let sidecarSize = FileSizing.regularFileSize(at: sidecar) {
                        paths.append(sidecar)
                        exclusive += sidecarSize
                    }
                }
            }
            let name = Self.cleanGGUFName(URL(fileURLWithPath: key).lastPathComponent)
            let parsed = ModelNameParser.parse(name)
            let isProjector = name.lowercased().contains("mmproj")
            entries.append(ModelEntry(
                id: "\(service.rawValue):" + relativeName(for: first),
                service: service,
                name: name,
                sizeBytes: total,
                revealURL: first,
                format: .gguf,
                category: ModelClassifier.classify(name: name, hints: ClassificationHints(hasProjector: isProjector)),
                parameterSize: parsed.parameterLabel,
                quantization: parsed.quantization,
                modifiedAt: FileSizing.modificationDate(at: first),
                exclusivePaths: paths,
                exclusiveBytes: exclusive,
                files: files
            ))
        }
        return entries
    }
}
