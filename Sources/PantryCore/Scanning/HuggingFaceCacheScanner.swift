import Foundation

/// Reads the standard Hugging Face hub cache:
/// `<hub>/models--<org>--<name>/{blobs,refs,snapshots/<revision>/...}`.
/// MLX models usually live here too, so repos that look like MLX conversions are
/// attributed to `.mlx`; everything else is `.huggingFace`.
public struct HuggingFaceCacheScanner: ModelScanner {
    public let hubRoot: URL
    public let minimumCandidateBytes: Int64
    public var label: String { "Hugging Face cache" }

    public init(hubRoot: URL, minimumCandidateBytes: Int64 = defaultDuplicateCandidateBytes) {
        self.hubRoot = hubRoot
        self.minimumCandidateBytes = minimumCandidateBytes
    }

    public func scan() throws -> [ModelEntry] {
        let fm = FileManager.default
        guard fm.fileExists(atPath: hubRoot.path) else { return [] }
        let children = try fm.contentsOfDirectory(
            at: hubRoot,
            includingPropertiesForKeys: [.isDirectoryKey],
            options: [.skipsHiddenFiles]
        )
        var entries: [ModelEntry] = []
        for dir in children where dir.lastPathComponent.hasPrefix("models--") {
            if let entry = makeEntry(repoDir: dir) { entries.append(entry) }
        }
        return entries
    }

    /// "models--mlx-community--Llama-3.2-3B-Instruct-4bit" -> "mlx-community/Llama-3.2-3B-Instruct-4bit"
    static func repoID(fromFolderName folder: String) -> String {
        let trimmed = String(folder.dropFirst("models--".count))
        return trimmed.components(separatedBy: "--").joined(separator: "/")
    }

    private func makeEntry(repoDir: URL) -> ModelEntry? {
        let fm = FileManager.default
        let repo = Self.repoID(fromFolderName: repoDir.lastPathComponent)
        let blobsDir = repoDir.appendingPathComponent("blobs", isDirectory: true)
        let size = FileSizing.directorySize(at: blobsDir)

        var isIncomplete = false
        if let blobNames = try? fm.contentsOfDirectory(atPath: blobsDir.path) {
            isIncomplete = blobNames.contains { $0.hasSuffix(".incomplete") }
        }
        if size == 0 && !isIncomplete { return nil }

        let snapshot = latestSnapshot(in: repoDir)
        var relativeFiles: [(path: String, url: URL)] = []
        if let snapshot, let enumerator = fm.enumerator(at: snapshot, includingPropertiesForKeys: nil, options: [.skipsHiddenFiles]) {
            for case let url as URL in enumerator {
                if let rel = PathSafety.relativeComponents(of: url, under: snapshot) {
                    relativeFiles.append((rel.joined(separator: "/"), url))
                }
            }
        }
        let names = relativeFiles.map { $0.path.lowercased() }

        let format: ModelFormat
        if names.contains("model_index.json") {
            format = .diffusers
        } else if names.contains(where: { $0.hasSuffix(".gguf") }) {
            format = .gguf
        } else if names.contains(where: { $0.hasSuffix(".safetensors") }) {
            format = .safetensors
        } else {
            format = .other
        }

        var architectures: [String] = []
        var configHasQuantization = false
        var quantBits: Int?
        if let configURL = relativeFiles.first(where: { $0.path == "config.json" })?.url,
           let data = try? Data(contentsOf: configURL),
           let json = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any] {
            architectures = (json["architectures"] as? [String]) ?? []
            if let q = json["quantization"] as? [String: Any] {
                configHasQuantization = true
                quantBits = q["bits"] as? Int
            }
        }

        var pipelineTag: String?
        if let readme = relativeFiles.first(where: { $0.path.lowercased() == "readme.md" })?.url {
            pipelineTag = Self.pipelineTag(inModelCard: readme)
        }

        let lowerRepo = repo.lowercased()
        let looksLikeMLX = lowerRepo.contains("mlx") || (configHasQuantization && format == .safetensors)
        let service: ModelService = looksLikeMLX ? .mlx : .huggingFace

        var files: [ModelFile] = []
        for item in relativeFiles {
            let lower = item.path.lowercased()
            guard lower.hasSuffix(".gguf") || lower.hasSuffix(".safetensors") else { continue }
            let resolved = item.url.resolvingSymlinksInPath()
            if let fileSize = FileSizing.regularFileSize(at: resolved), fileSize >= minimumCandidateBytes {
                files.append(ModelFile(url: resolved, size: fileSize))
            }
        }

        let parsed = ModelNameParser.parse(repo)
        var quantization = parsed.quantization
        if quantization == nil, let quantBits { quantization = "\(quantBits)-bit" }
        if quantization == nil, format == .gguf {
            let ggufNames = relativeFiles.map { $0.path }.filter { $0.lowercased().hasSuffix(".gguf") }
            if ggufNames.count == 1 { quantization = ModelNameParser.parse(ggufNames[0]).quantization }
        }

        let category = ModelClassifier.classify(
            name: repo,
            hints: ClassificationHints(
                architectures: architectures,
                isDiffusers: format == .diffusers,
                pipelineTag: pipelineTag
            )
        )

        return ModelEntry(
            id: "hf:" + repoDir.lastPathComponent,
            service: service,
            name: repo,
            sizeBytes: size,
            revealURL: snapshot ?? repoDir,
            format: format,
            category: category,
            parameterSize: parsed.parameterLabel,
            quantization: quantization,
            modifiedAt: FileSizing.modificationDate(at: repoDir),
            exclusivePaths: [repoDir],
            exclusiveBytes: size,
            blobs: [],
            files: files,
            isIncomplete: isIncomplete
        )
    }

    private func latestSnapshot(in repoDir: URL) -> URL? {
        let fm = FileManager.default
        let refsMain = repoDir.appendingPathComponent("refs/main")
        let snapshots = repoDir.appendingPathComponent("snapshots", isDirectory: true)
        if let revision = try? String(contentsOf: refsMain, encoding: .utf8) {
            let candidate = snapshots.appendingPathComponent(revision.trimmingCharacters(in: .whitespacesAndNewlines), isDirectory: true)
            if fm.fileExists(atPath: candidate.path) { return candidate }
        }
        guard let names = try? fm.contentsOfDirectory(atPath: snapshots.path), let first = names.sorted().first else { return nil }
        return snapshots.appendingPathComponent(first, isDirectory: true)
    }

    /// Reads `pipeline_tag:` from the YAML front matter of a model card.
    static func pipelineTag(inModelCard url: URL) -> String? {
        guard let handle = try? FileHandle(forReadingFrom: url) else { return nil }
        defer { try? handle.close() }
        guard let data = try? handle.read(upToCount: 4096),
              let text = String(data: data, encoding: .utf8), text.hasPrefix("---") else { return nil }
        for line in text.split(separator: "\n", omittingEmptySubsequences: true).dropFirst() {
            if line.hasPrefix("---") { break }
            if line.hasPrefix("pipeline_tag:") {
                return line.dropFirst("pipeline_tag:".count).trimmingCharacters(in: .whitespaces)
            }
        }
        return nil
    }
}
