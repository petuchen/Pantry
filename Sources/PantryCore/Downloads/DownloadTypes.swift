import Foundation

public struct DownloadProgress: Equatable, Sendable {
    public var phase: String
    public var completedBytes: Int64
    public var totalBytes: Int64?

    public init(phase: String, completedBytes: Int64 = 0, totalBytes: Int64? = nil) {
        self.phase = phase
        self.completedBytes = completedBytes
        self.totalBytes = totalBytes
    }

    /// 0...1, or nil when the total is not known yet.
    public var fraction: Double? {
        guard let total = totalBytes, total > 0 else { return nil }
        return min(1.0, Double(completedBytes) / Double(total))
    }
}

/// Error messages say what happened and what to do next, and never blame the user.
public enum DownloadError: LocalizedError, Equatable {
    case ollamaNotRunning
    case invalidReference(String)
    case needsAuthentication
    case notFound
    case http(Int)
    case remote(String)
    case notEnoughSpace(needed: Int64, available: Int64)
    case unexpectedResponse

    public var errorDescription: String? {
        switch self {
        case .ollamaNotRunning:
            return "Ollama isn't running. Open the Ollama app (or run `ollama serve` in Terminal), then try again."
        case .invalidReference(let text):
            return "“\(text)” doesn't look like a model name we can use. Try something like llama3.2:3b."
        case .needsAuthentication:
            return "This model needs a Hugging Face access token. Accept its terms on huggingface.co and sign in with `hf auth login`, then try again."
        case .notFound:
            return "That model wasn't found. Check the name for typos."
        case .http(let code):
            return "The server answered with an unexpected status (\(code)). Try again in a moment."
        case .remote(let message):
            return message
        case .notEnoughSpace(let needed, let available):
            return "This download needs \(ByteFormat.string(needed)) but only \(ByteFormat.string(available)) is free."
        case .unexpectedResponse:
            return "The server's answer wasn't in the expected format."
        }
    }
}
