import Foundation

public struct ScanWarning: Hashable, Sendable {
    public let source: String
    public let message: String
    public init(source: String, message: String) {
        self.source = source
        self.message = message
    }
}

/// One folder that was (or would have been) scanned, so an empty library can explain itself.
public struct ScannedFolder: Hashable, Sendable, Identifiable {
    public let service: ModelService
    public let url: URL
    public let exists: Bool
    public var id: String { service.rawValue + ":" + url.path }
    public init(service: ModelService, url: URL, exists: Bool) {
        self.service = service
        self.url = url
        self.exists = exists
    }
}

public struct ScanResult: Sendable {
    public var entries: [ModelEntry]
    public var warnings: [ScanWarning]
    public var folders: [ScannedFolder]
}

public enum ModelLibrary {
    /// Builds the scanners for the given locations.
    public static func scanners(for locations: ScanLocations, minimumCandidateBytes: Int64 = defaultDuplicateCandidateBytes) -> [any ModelScanner] {
        var scanners: [any ModelScanner] = [
            OllamaScanner(root: locations.ollamaRoot),
            HuggingFaceCacheScanner(hubRoot: locations.huggingFaceHub, minimumCandidateBytes: minimumCandidateBytes),
        ]
        for folder in locations.llamaCppFolders {
            scanners.append(LooseFolderScanner(root: folder, service: .llamaCpp, minimumCandidateBytes: minimumCandidateBytes))
        }
        for custom in locations.customFolders {
            if looksLikeHuggingFaceCache(custom.url) {
                scanners.append(HuggingFaceCacheScanner(hubRoot: custom.url, minimumCandidateBytes: minimumCandidateBytes))
            } else {
                scanners.append(LooseFolderScanner(root: custom.url, service: custom.service, minimumCandidateBytes: minimumCandidateBytes))
            }
        }
        return scanners
    }

    public static func folders(for locations: ScanLocations) -> [ScannedFolder] {
        let fm = FileManager.default
        func folder(_ service: ModelService, _ url: URL) -> ScannedFolder {
            ScannedFolder(service: service, url: url, exists: fm.fileExists(atPath: url.path))
        }
        var result = [
            folder(.ollama, locations.ollamaRoot),
            folder(.huggingFace, locations.huggingFaceHub),
        ]
        result.append(contentsOf: locations.llamaCppFolders.map { folder(.llamaCpp, $0) })
        result.append(contentsOf: locations.customFolders.map { folder($0.service, $0.url) })
        return result
    }

    /// Runs every scanner concurrently. A failing scanner becomes a warning; the others still report.
    public static func scan(locations: ScanLocations, minimumCandidateBytes: Int64 = defaultDuplicateCandidateBytes) async -> ScanResult {
        let activeScanners = scanners(for: locations, minimumCandidateBytes: minimumCandidateBytes)
        var entries: [ModelEntry] = []
        var warnings: [ScanWarning] = []

        await withTaskGroup(of: (entries: [ModelEntry], warning: ScanWarning?).self) { group in
            for scanner in activeScanners {
                group.addTask {
                    do {
                        return (try scanner.scan(), nil)
                    } catch {
                        return ([], ScanWarning(source: scanner.label, message: error.localizedDescription))
                    }
                }
            }
            for await result in group {
                entries.append(contentsOf: result.entries)
                if let warning = result.warning { warnings.append(warning) }
            }
        }

        // A custom folder nested inside a default one must not list models twice.
        var seen = Set<String>()
        entries = entries.filter { seen.insert($0.id).inserted }
        entries.sort { $0.sizeBytes > $1.sizeBytes }
        return ScanResult(entries: entries, warnings: warnings, folders: folders(for: locations))
    }

    private static func looksLikeHuggingFaceCache(_ url: URL) -> Bool {
        guard let names = try? FileManager.default.contentsOfDirectory(atPath: url.path) else { return false }
        return names.contains { $0.hasPrefix("models--") }
    }
}
