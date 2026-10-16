import Foundation

/// Folds Ollama's streamed `/api/pull` lines (one JSON object per line) into a single
/// overall progress value. Ollama reports each layer separately; we sum them.
public struct OllamaPullProgressAggregator {
    private var layers: [String: (total: Int64, completed: Int64)] = [:]
    public private(set) var isFinished = false

    public init() {}

    /// Returns nil for lines that carry no usable information. Throws on an `error` line.
    public mutating func ingest(line: String) throws -> DownloadProgress? {
        guard let data = line.data(using: .utf8),
              let json = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any] else { return nil }

        if let message = json["error"] as? String { throw DownloadError.remote(message) }
        guard let status = json["status"] as? String else { return nil }

        if status == "success" {
            isFinished = true
            let total = layers.values.reduce(Int64(0)) { $0 + $1.total }
            return DownloadProgress(phase: "Done", completedBytes: total, totalBytes: total)
        }

        if let digest = json["digest"] as? String, let total = (json["total"] as? NSNumber)?.int64Value {
            let completed = (json["completed"] as? NSNumber)?.int64Value ?? layers[digest]?.completed ?? 0
            layers[digest] = (total, completed)
        }

        let total = layers.values.reduce(Int64(0)) { $0 + $1.total }
        let completed = layers.values.reduce(Int64(0)) { $0 + $1.completed }
        return DownloadProgress(
            phase: Self.friendlyPhase(status),
            completedBytes: completed,
            totalBytes: total > 0 ? total : nil
        )
    }

    static func friendlyPhase(_ status: String) -> String {
        let lower = status.lowercased()
        if lower.contains("manifest") && lower.hasPrefix("pulling") { return "Fetching details" }
        if lower.hasPrefix("pulling") { return "Downloading" }
        if lower.contains("verifying") { return "Verifying" }
        if lower.contains("writing") { return "Finishing up" }
        return status.prefix(1).uppercased() + status.dropFirst()
    }
}

public struct OllamaPuller: Sendable {
    public let baseURL: URL

    public init(baseURL: URL = URL(string: "http://127.0.0.1:11434")!) {
        self.baseURL = baseURL
    }

    public func isReachable() async -> Bool {
        var request = URLRequest(url: baseURL.appendingPathComponent("api/version"))
        request.timeoutInterval = 2
        guard let (_, response) = try? await URLSession.shared.data(for: request) else { return false }
        return (response as? HTTPURLResponse)?.statusCode == 200
    }

    public func pull(model: String, onProgress: @escaping @Sendable (DownloadProgress) -> Void) async throws {
        var request = URLRequest(url: baseURL.appendingPathComponent("api/pull"))
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.timeoutInterval = 120
        request.httpBody = try JSONSerialization.data(withJSONObject: ["model": model, "stream": true])

        let bytes: URLSession.AsyncBytes
        let response: URLResponse
        do {
            (bytes, response) = try await URLSession.shared.bytes(for: request)
        } catch let error as URLError where [.cannotConnectToHost, .networkConnectionLost, .cannotFindHost, .timedOut].contains(error.code) {
            throw DownloadError.ollamaNotRunning
        }
        guard let http = response as? HTTPURLResponse else { throw DownloadError.unexpectedResponse }
        guard http.statusCode == 200 else {
            if http.statusCode == 404 { throw DownloadError.notFound }
            throw DownloadError.http(http.statusCode)
        }

        var aggregator = OllamaPullProgressAggregator()
        onProgress(DownloadProgress(phase: "Starting"))
        for try await line in bytes.lines {
            try Task.checkCancellation()
            if let progress = try aggregator.ingest(line: line) { onProgress(progress) }
        }
        if !aggregator.isFinished { throw DownloadError.unexpectedResponse }
    }
}
