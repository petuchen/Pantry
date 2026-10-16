import Foundation

/// Reads `<root>/manifests/<host>/<namespace>/<name>/<tag>` (OCI-style manifests) and
/// `<root>/blobs/sha256-<hex>` (content-addressed layers).
public struct OllamaScanner: ModelScanner {
    public let root: URL
    public var label: String { "Ollama" }

    public init(root: URL) {
        self.root = root
    }

    private struct Manifest: Decodable {
        struct Layer: Decodable {
            let mediaType: String?
            let digest: String
            let size: Int64?
        }
        let config: Layer?
        let layers: [Layer]?
    }

    public func scan() throws -> [ModelEntry] {
        let fm = FileManager.default
        let manifestsRoot = root.appendingPathComponent("manifests", isDirectory: true)
        guard fm.fileExists(atPath: manifestsRoot.path) else { return [] }
        let blobsRoot = root.appendingPathComponent("blobs", isDirectory: true)

        guard let enumerator = fm.enumerator(
            at: manifestsRoot,
            includingPropertiesForKeys: [.isRegularFileKey],
            options: [.skipsHiddenFiles]
        ) else { return [] }

        var entries: [ModelEntry] = []
        for case let url as URL in enumerator {
            guard (try? url.resourceValues(forKeys: [.isRegularFileKey]))?.isRegularFile == true else { continue }
            guard let components = PathSafety.relativeComponents(of: url, under: manifestsRoot), components.count >= 4 else { continue }
            if let entry = makeEntry(manifestURL: url, components: components, blobsRoot: blobsRoot) {
                entries.append(entry)
            }
        }
        return entries
    }

    private func makeEntry(manifestURL: URL, components: [String], blobsRoot: URL) -> ModelEntry? {
        guard let data = try? Data(contentsOf: manifestURL),
              let manifest = try? JSONDecoder().decode(Manifest.self, from: data) else { return nil }

        let host = components[0]
        let namespace = components[1]
        let tag = components[components.count - 1]
        let repoName = components[2..<(components.count - 1)].joined(separator: "/")
        let displayName = Self.displayName(host: host, namespace: namespace, name: repoName, tag: tag)

        var allLayers: [Manifest.Layer] = []
        if let config = manifest.config { allLayers.append(config) }
        allLayers.append(contentsOf: manifest.layers ?? [])

        var blobs: [BlobRef] = []
        var files: [ModelFile] = []
        var isIncomplete = false
        var hasProjector = false
        var modelBlobURL: URL?

        for layer in allLayers {
            let hex = Self.hex(fromDigest: layer.digest)
            let blobURL = blobsRoot.appendingPathComponent("sha256-" + hex)
            guard let size = FileSizing.regularFileSize(at: blobURL) else {
                isIncomplete = true
                continue
            }
            blobs.append(BlobRef(digest: hex, url: blobURL, size: size))
            switch layer.mediaType ?? "" {
            case "application/vnd.ollama.image.model":
                modelBlobURL = blobURL
                files.append(ModelFile(url: blobURL, size: size, knownSHA256: hex))
            case "application/vnd.ollama.image.projector":
                hasProjector = true
            default:
                break
            }
        }

        var parameterSize: String?
        var quantization: String?
        var families: [String] = []
        if let configLayer = manifest.config {
            let configURL = blobsRoot.appendingPathComponent("sha256-" + Self.hex(fromDigest: configLayer.digest))
            if let configData = try? Data(contentsOf: configURL),
               let json = (try? JSONSerialization.jsonObject(with: configData)) as? [String: Any] {
                parameterSize = json["model_type"] as? String
                quantization = json["file_type"] as? String
                if let family = json["model_family"] as? String { families.append(family) }
                if let more = json["model_families"] as? [String] { families.append(contentsOf: more) }
            }
        }

        let parsed = ModelNameParser.parse(displayName)
        let manifestSize = FileSizing.regularFileSize(at: manifestURL) ?? 0
        let blobTotal = blobs.reduce(Int64(0)) { $0 + $1.size }
        let category = ModelClassifier.classify(
            name: displayName,
            hints: ClassificationHints(families: families, hasProjector: hasProjector)
        )

        return ModelEntry(
            id: "ollama:" + components.joined(separator: "/"),
            service: .ollama,
            name: displayName,
            sizeBytes: blobTotal + manifestSize,
            revealURL: modelBlobURL ?? manifestURL,
            format: .gguf,
            category: category,
            parameterSize: parameterSize ?? parsed.parameterLabel,
            quantization: quantization ?? parsed.quantization,
            modifiedAt: FileSizing.modificationDate(at: manifestURL),
            exclusivePaths: [manifestURL],
            exclusiveBytes: manifestSize,
            blobs: blobs,
            files: files,
            isIncomplete: isIncomplete
        )
    }

    /// "registry.ollama.ai/library/llama3.2/3b" -> "llama3.2:3b"
    static func displayName(host: String, namespace: String, name: String, tag: String) -> String {
        if host == "registry.ollama.ai" {
            return namespace == "library" ? "\(name):\(tag)" : "\(namespace)/\(name):\(tag)"
        }
        return "\(host)/\(namespace)/\(name):\(tag)"
    }

    /// "sha256:abc" -> "abc"
    static func hex(fromDigest digest: String) -> String {
        if let colon = digest.firstIndex(of: ":") {
            return String(digest[digest.index(after: colon)...])
        }
        return digest.replacingOccurrences(of: "sha256-", with: "")
    }
}
