import Foundation

// MARK: - Public types

public struct HFRepoSummary: Identifiable, Hashable, Sendable, Decodable {
    public let id: String
    public let downloads: Int
    public let likes: Int
    public let pipelineTag: String?
    public let tags: [String]

    enum CodingKeys: String, CodingKey {
        case id, modelId, downloads, likes, tags
        case pipelineTag = "pipeline_tag"
    }

    public init(id: String, downloads: Int = 0, likes: Int = 0, pipelineTag: String? = nil, tags: [String] = []) {
        self.id = id
        self.downloads = downloads
        self.likes = likes
        self.pipelineTag = pipelineTag
        self.tags = tags
    }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        let primary = try c.decodeIfPresent(String.self, forKey: .id)
        let fallback = try c.decodeIfPresent(String.self, forKey: .modelId)
        guard let resolved = primary ?? fallback else {
            throw DecodingError.keyNotFound(CodingKeys.id, DecodingError.Context(codingPath: decoder.codingPath, debugDescription: "No repo id"))
        }
        self.id = resolved
        self.downloads = (try? c.decodeIfPresent(Int.self, forKey: .downloads)) ?? 0
        self.likes = (try? c.decodeIfPresent(Int.self, forKey: .likes)) ?? 0
        self.pipelineTag = try? c.decodeIfPresent(String.self, forKey: .pipelineTag)
        self.tags = (try? c.decodeIfPresent([String].self, forKey: .tags)) ?? []
    }
}

public struct HFRepoFile: Hashable, Sendable {
    public let path: String
    public let size: Int64
    public let sha256: String?
    public let blobId: String?

    public init(path: String, size: Int64, sha256: String? = nil, blobId: String? = nil) {
        self.path = path
        self.size = size
        self.sha256 = sha256
        self.blobId = blobId
    }

    /// The name hf-hub uses for the blob: the LFS SHA-256 for big files, the git blob id otherwise.
    public var etag: String {
        if let sha256, !sha256.isEmpty { return sha256 }
        if let blobId, !blobId.isEmpty { return blobId }
        return "pantry-" + path.replacingOccurrences(of: "/", with: "_")
    }

    public var isGGUF: Bool { path.lowercased().hasSuffix(".gguf") }
}

public struct HFRepoDetails: Hashable, Sendable {
    public let id: String
    /// Commit SHA that `files` belong to.
    public let revision: String
    public let files: [HFRepoFile]

    public init(id: String, revision: String, files: [HFRepoFile]) {
        self.id = id
        self.revision = revision
        self.files = files
    }

    public var totalBytes: Int64 { files.reduce(Int64(0)) { $0 + $1.size } }
    public var ggufFiles: [HFRepoFile] { files.filter { $0.isGGUF }.sorted { $0.size < $1.size } }
}

public enum HFSearchFilter: String, Sendable {
    case any
    case mlx
    case gguf
}

public enum HFToken {
    /// Reads the token the way the official CLI does, so `hf auth login` once is enough.
    /// Finder-launched apps do not inherit shell environment variables, hence the file fallback.
    public static func load(
        environment: [String: String] = ProcessInfo.processInfo.environment,
        home: URL = FileManager.default.homeDirectoryForCurrentUser
    ) -> String? {
        for key in ["HF_TOKEN", "HUGGING_FACE_HUB_TOKEN"] {
            if let value = environment[key]?.trimmingCharacters(in: .whitespacesAndNewlines), !value.isEmpty { return value }
        }
        var candidates: [URL] = []
        if let hfHome = environment["HF_HOME"] {
            candidates.append(URL(fileURLWithPath: hfHome).appendingPathComponent("token"))
        }
        candidates.append(home.appendingPathComponent(".cache/huggingface/token"))
        for url in candidates {
            if let text = try? String(contentsOf: url, encoding: .utf8) {
                let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
                if !trimmed.isEmpty { return trimmed }
            }
        }
        return nil
    }
}

// MARK: - Client

public struct HuggingFaceClient: Sendable {
    public let baseURL: URL
    public let token: String?

    public init(baseURL: URL = URL(string: "https://huggingface.co")!, token: String? = HFToken.load()) {
        self.baseURL = baseURL
        self.token = token
    }

    public var hasToken: Bool { token != nil }

    public func search(query: String, filter: HFSearchFilter, limit: Int = 20) async throws -> [HFRepoSummary] {
        var components = URLComponents(url: baseURL.appendingPathComponent("api/models"), resolvingAgainstBaseURL: false)!
        var items = [
            URLQueryItem(name: "sort", value: "downloads"),
            URLQueryItem(name: "direction", value: "-1"),
            URLQueryItem(name: "limit", value: String(limit)),
        ]
        let trimmed = query.trimmingCharacters(in: .whitespacesAndNewlines)
        if !trimmed.isEmpty { items.append(URLQueryItem(name: "search", value: trimmed)) }
        if filter != .any { items.append(URLQueryItem(name: "filter", value: filter.rawValue)) }
        components.queryItems = items
        let data = try await fetch(components.url!)
        return try Self.decodeSearch(data)
    }

    public func details(repo: String) async throws -> HFRepoDetails {
        var components = URLComponents(url: baseURL, resolvingAgainstBaseURL: false)!
        components.path = "/api/models/" + repo
        components.queryItems = [URLQueryItem(name: "blobs", value: "true")]
        let data = try await fetch(components.url!)
        return try Self.decodeDetails(data, fallbackID: repo)
    }

    public func resolveURL(repo: String, revision: String, path: String) -> URL {
        var components = URLComponents(url: baseURL, resolvingAgainstBaseURL: false)!
        components.path = "/\(repo)/resolve/\(revision)/\(path)"
        return components.url!
    }

    public func authorizedRequest(_ url: URL) -> URLRequest {
        var request = URLRequest(url: url)
        request.timeoutInterval = 60
        if let token, url.host == baseURL.host { request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization") }
        return request
    }

    private func fetch(_ url: URL) async throws -> Data {
        let (data, response) = try await URLSession.shared.data(for: authorizedRequest(url))
        guard let http = response as? HTTPURLResponse else { throw DownloadError.unexpectedResponse }
        switch http.statusCode {
        case 200: return data
        case 401, 403: throw DownloadError.needsAuthentication
        case 404: throw DownloadError.notFound
        default: throw DownloadError.http(http.statusCode)
        }
    }

    // MARK: Decoding (static so it is unit-testable without a network)

    public static func decodeSearch(_ data: Data) throws -> [HFRepoSummary] {
        try JSONDecoder().decode([HFRepoSummary].self, from: data)
    }

    public static func decodeDetails(_ data: Data, fallbackID: String) throws -> HFRepoDetails {
        struct Sibling: Decodable {
            struct LFS: Decodable { let sha256: String?; let size: Int64? }
            let rfilename: String
            let size: Int64?
            let blobId: String?
            let lfs: LFS?
        }
        struct Payload: Decodable {
            let id: String?
            let sha: String?
            let siblings: [Sibling]?
        }
        let payload = try JSONDecoder().decode(Payload.self, from: data)
        guard let sha = payload.sha, !sha.isEmpty else { throw DownloadError.unexpectedResponse }
        let files = (payload.siblings ?? []).map { sibling in
            HFRepoFile(
                path: sibling.rfilename,
                size: sibling.lfs?.size ?? sibling.size ?? 0,
                sha256: sibling.lfs?.sha256,
                blobId: sibling.blobId
            )
        }
        return HFRepoDetails(id: payload.id ?? fallbackID, revision: sha, files: files)
    }
}
