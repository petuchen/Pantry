import Foundation

/// A folder the user added in Settings, assigned to a service.
public struct CustomFolder: Codable, Hashable, Sendable, Identifiable {
    public var path: String
    public var service: ModelService
    public var id: String { path }
    public var url: URL { URL(fileURLWithPath: path, isDirectory: true) }

    public init(path: String, service: ModelService) {
        self.path = path
        self.service = service
    }
}

/// Where Pantry looks for models. Defaults follow each tool's own environment variables.
public struct ScanLocations: Sendable {
    public var ollamaRoot: URL
    public var huggingFaceHub: URL
    public var llamaCppFolders: [URL]
    public var customFolders: [CustomFolder]

    public init(ollamaRoot: URL, huggingFaceHub: URL, llamaCppFolders: [URL], customFolders: [CustomFolder] = []) {
        self.ollamaRoot = ollamaRoot
        self.huggingFaceHub = huggingFaceHub
        self.llamaCppFolders = llamaCppFolders
        self.customFolders = customFolders
    }

    public static func defaults(
        environment: [String: String] = ProcessInfo.processInfo.environment,
        home: URL = FileManager.default.homeDirectoryForCurrentUser,
        customFolders: [CustomFolder] = []
    ) -> ScanLocations {
        func dir(_ path: String) -> URL { URL(fileURLWithPath: path, isDirectory: true) }

        let ollama = environment["OLLAMA_MODELS"].map(dir)
            ?? home.appendingPathComponent(".ollama/models", isDirectory: true)

        let hub: URL
        if let explicit = environment["HF_HUB_CACHE"] {
            hub = dir(explicit)
        } else if let hfHome = environment["HF_HOME"] {
            hub = dir(hfHome).appendingPathComponent("hub", isDirectory: true)
        } else if let xdg = environment["XDG_CACHE_HOME"] {
            hub = dir(xdg).appendingPathComponent("huggingface/hub", isDirectory: true)
        } else {
            hub = home.appendingPathComponent(".cache/huggingface/hub", isDirectory: true)
        }

        let llama = environment["LLAMA_CACHE"].map(dir)
            ?? home.appendingPathComponent("Library/Caches/llama.cpp", isDirectory: true)

        return ScanLocations(ollamaRoot: ollama, huggingFaceHub: hub, llamaCppFolders: [llama], customFolders: customFolders)
    }

    /// Every folder Pantry is allowed to modify. `RemovalExecutor` refuses anything outside these.
    public var allRoots: [URL] {
        [ollamaRoot, huggingFaceHub] + llamaCppFolders + customFolders.map { $0.url }
    }

    /// Where a download for `service` should land by default.
    public func downloadFolder(for service: ModelService) -> URL {
        switch service {
        case .ollama: return ollamaRoot
        case .huggingFace, .mlx: return huggingFaceHub
        case .llamaCpp: return llamaCppFolders.first ?? huggingFaceHub
        }
    }
}
