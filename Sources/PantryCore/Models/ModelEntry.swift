import Foundation

public enum ModelFormat: String, Codable, Hashable, Sendable {
    case gguf
    case safetensors
    case diffusers
    case other

    public var displayName: String {
        switch self {
        case .gguf: return "GGUF"
        case .safetensors: return "Safetensors"
        case .diffusers: return "Diffusers"
        case .other: return "Other"
        }
    }
}

/// A content-addressed file that may be shared between several models
/// (Ollama stores layers as `blobs/sha256-<hex>`; two tags can share one).
public struct BlobRef: Hashable, Sendable {
    public let digest: String
    public let url: URL
    public let size: Int64

    public init(digest: String, url: URL, size: Int64) {
        self.digest = digest
        self.url = url
        self.size = size
    }
}

/// A large weights file used for exact-duplicate detection.
public struct ModelFile: Hashable, Sendable {
    public let url: URL
    public let size: Int64
    /// Set when the store already tells us the SHA-256 (Ollama blob names), so we never re-hash it.
    public let knownSHA256: String?

    public init(url: URL, size: Int64, knownSHA256: String? = nil) {
        self.url = url
        self.size = size
        self.knownSHA256 = knownSHA256
    }
}

/// One model as the user thinks of it: "llama3.2:3b", "mlx-community/Qwen2.5-7B-4bit", a .gguf file.
public struct ModelEntry: Identifiable, Hashable, Sendable {
    public let id: String
    public let service: ModelService
    public let name: String
    public let format: ModelFormat
    public var category: ModelCategory
    /// e.g. "3.2B"
    public let parameterSize: String?
    /// e.g. "Q4_K_M", "4-bit"
    public let quantization: String?
    /// Apparent size: what this model alone would occupy. Shared blobs are counted in full here.
    public let sizeBytes: Int64
    public let modifiedAt: Date?
    /// What "Reveal in Finder" should select.
    public let revealURL: URL
    /// Paths that belong to this model alone; removing the model removes them.
    public let exclusivePaths: [URL]
    /// Bytes inside `exclusivePaths`.
    public let exclusiveBytes: Int64
    /// Shared, content-addressed blobs. Only removed when no other model references them.
    public let blobs: [BlobRef]
    public let files: [ModelFile]
    /// An interrupted download: some expected data is missing or still `.incomplete`.
    public let isIncomplete: Bool

    public init(
        id: String,
        service: ModelService,
        name: String,
        sizeBytes: Int64,
        revealURL: URL,
        format: ModelFormat = .other,
        category: ModelCategory = .uncategorized,
        parameterSize: String? = nil,
        quantization: String? = nil,
        modifiedAt: Date? = nil,
        exclusivePaths: [URL] = [],
        exclusiveBytes: Int64 = 0,
        blobs: [BlobRef] = [],
        files: [ModelFile] = [],
        isIncomplete: Bool = false
    ) {
        self.id = id
        self.service = service
        self.name = name
        self.format = format
        self.category = category
        self.parameterSize = parameterSize
        self.quantization = quantization
        self.sizeBytes = sizeBytes
        self.modifiedAt = modifiedAt
        self.revealURL = revealURL
        self.exclusivePaths = exclusivePaths
        self.exclusiveBytes = exclusiveBytes
        self.blobs = blobs
        self.files = files
        self.isIncomplete = isIncomplete
    }

    /// Sort key that works with `KeyPathComparator`.
    public var modifiedSortKey: Date { modifiedAt ?? Date.distantPast }

    /// "3.2B · Q4_K_M · GGUF"
    public var technicalSummary: String {
        var parts: [String] = []
        if let parameterSize { parts.append(parameterSize) }
        if let quantization { parts.append(quantization) }
        parts.append(format.displayName)
        return parts.joined(separator: " · ")
    }
}
