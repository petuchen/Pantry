import Foundation

/// The runtime / ecosystem a model lives in. A model's service decides where
/// it is stored and how it is pulled or removed.
public enum ModelService: String, CaseIterable, Codable, Hashable, Sendable, Identifiable {
    case ollama
    case llamaCpp
    case mlx
    case huggingFace
    /// Any other tool (LM Studio, Jan, ...). Only reachable through a user-added folder.
    case other

    public var id: String { rawValue }

    public var displayName: String {
        switch self {
        case .ollama: return "Ollama"
        case .llamaCpp: return "llama.cpp"
        case .mlx: return "MLX"
        case .huggingFace: return "Hugging Face"
        case .other: return "Other"
        }
    }

    /// SF Symbol. Services are always identified by name + symbol, never by colour alone.
    public var symbolName: String {
        switch self {
        case .ollama: return "shippingbox"
        case .llamaCpp: return "terminal"
        case .mlx: return "cpu"
        case .huggingFace: return "face.smiling"
        case .other: return "folder"
        }
    }
}
