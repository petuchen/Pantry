import Foundation
import CryptoKit
import XCTest
@testable import PantryCore

/// A throwaway directory that deletes itself.
final class TempDir {
    let url: URL

    init() throws {
        url = FileManager.default.temporaryDirectory
            .appendingPathComponent("pantry-tests-" + UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
    }

    deinit { try? FileManager.default.removeItem(at: url) }

    @discardableResult
    func file(_ relativePath: String, bytes: Int = 0, fill: UInt8 = 0) throws -> URL {
        let target = url.appendingPathComponent(relativePath)
        try FileManager.default.createDirectory(at: target.deletingLastPathComponent(), withIntermediateDirectories: true)
        try Data(repeating: fill, count: bytes).write(to: target)
        return target
    }

    @discardableResult
    func file(_ relativePath: String, text: String) throws -> URL {
        let target = url.appendingPathComponent(relativePath)
        try FileManager.default.createDirectory(at: target.deletingLastPathComponent(), withIntermediateDirectories: true)
        try text.write(to: target, atomically: true, encoding: .utf8)
        return target
    }

    @discardableResult
    func directory(_ relativePath: String) throws -> URL {
        let target = url.appendingPathComponent(relativePath, isDirectory: true)
        try FileManager.default.createDirectory(at: target, withIntermediateDirectories: true)
        return target
    }

    func exists(_ relativePath: String) -> Bool {
        FileManager.default.fileExists(atPath: url.appendingPathComponent(relativePath).path)
    }
}

enum Fixtures {
    static func sha256Hex(_ data: Data) -> String {
        SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined()
    }

    struct Layer {
        var mediaType: String
        var data: Data
        static func model(bytes: Int, fill: UInt8 = 1) -> Layer {
            Layer(mediaType: "application/vnd.ollama.image.model", data: Data(repeating: fill, count: bytes))
        }
        static func template(_ text: String = "{{ .Prompt }}") -> Layer {
            Layer(mediaType: "application/vnd.ollama.image.template", data: Data(text.utf8))
        }
        static func projector(bytes: Int) -> Layer {
            Layer(mediaType: "application/vnd.ollama.image.projector", data: Data(repeating: 9, count: bytes))
        }
    }

    /// Writes a realistic Ollama store entry. Returns the blob hex digests (config first, then layers).
    @discardableResult
    static func ollamaModel(
        root: URL,
        host: String = "registry.ollama.ai",
        namespace: String = "library",
        name: String,
        tag: String,
        layers: [Layer],
        config: [String: Any]? = ["model_format": "gguf", "model_type": "3.2B", "file_type": "Q4_K_M", "model_family": "llama", "model_families": ["llama"]],
        writeBlobs: Bool = true
    ) throws -> [String] {
        let fm = FileManager.default
        let blobs = root.appendingPathComponent("blobs", isDirectory: true)
        try fm.createDirectory(at: blobs, withIntermediateDirectories: true)

        func store(_ data: Data) throws -> String {
            let hex = sha256Hex(data)
            if writeBlobs { try data.write(to: blobs.appendingPathComponent("sha256-" + hex)) }
            return hex
        }

        var digests: [String] = []
        var manifest: [String: Any] = ["schemaVersion": 2]
        if let config {
            // sortedKeys: Swift dictionaries iterate in a per-instance order, so without it two
            // identical configs could serialize differently (and hash to different blobs).
            let data = try JSONSerialization.data(withJSONObject: config, options: [.sortedKeys])
            let hex = try store(data)
            digests.append(hex)
            manifest["config"] = ["mediaType": "application/vnd.docker.container.image.v1+json", "digest": "sha256:" + hex, "size": data.count]
        }
        var layerJSON: [[String: Any]] = []
        for layer in layers {
            let hex = try store(layer.data)
            digests.append(hex)
            layerJSON.append(["mediaType": layer.mediaType, "digest": "sha256:" + hex, "size": layer.data.count])
        }
        manifest["layers"] = layerJSON

        let manifestDir = root.appendingPathComponent("manifests/\(host)/\(namespace)/\(name)", isDirectory: true)
        try fm.createDirectory(at: manifestDir, withIntermediateDirectories: true)
        try JSONSerialization.data(withJSONObject: manifest, options: [.sortedKeys]).write(to: manifestDir.appendingPathComponent(tag))
        return digests
    }

    /// Writes a Hugging Face hub cache repo with real symlinks. `files` maps path -> (etag, data).
    @discardableResult
    static func huggingFaceRepo(
        hub: URL,
        repo: String,
        revision: String = "abc123",
        files: [(path: String, etag: String, data: Data)],
        extraBlobs: [(name: String, bytes: Int)] = []
    ) throws -> URL {
        let layout = HFCacheLayout(hubRoot: hub)
        let fm = FileManager.default
        try fm.createDirectory(at: layout.blobsDir(for: repo), withIntermediateDirectories: true)
        for file in files {
            try file.data.write(to: layout.blobURL(repo: repo, etag: file.etag))
        }
        for extra in extraBlobs {
            try Data(count: extra.bytes).write(to: layout.blobURL(repo: repo, etag: extra.name))
        }
        try layout.commit(repo: repo, revision: revision, files: files.map { ($0.path, $0.etag) })
        return layout.repoDir(for: repo)
    }

    static func entry(
        _ name: String,
        service: ModelService = .ollama,
        size: Int64 = 1_000,
        parameterSize: String? = nil,
        id: String? = nil
    ) -> ModelEntry {
        ModelEntry(
            id: id ?? "\(service.rawValue):\(name)",
            service: service,
            name: name,
            sizeBytes: size,
            revealURL: URL(fileURLWithPath: "/tmp/\(name)"),
            parameterSize: parameterSize,
            exclusiveBytes: size
        )
    }
}

/// Counts how often the duplicate detector had to read a file.
final class CallCounter: @unchecked Sendable {
    private let lock = NSLock()
    private var value = 0
    func increment() { lock.lock(); value += 1; lock.unlock() }
    var count: Int { lock.lock(); defer { lock.unlock() }; return value }
}
