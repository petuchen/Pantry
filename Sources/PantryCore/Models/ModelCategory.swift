import Foundation

/// What a model is *for*. Derived heuristically (see `ModelClassifier`) and
/// always user-overridable in the app.
public enum ModelCategory: String, CaseIterable, Codable, Hashable, Sendable, Identifiable {
    case general
    case coding
    case reasoning
    case vision
    case imageGeneration
    case embedding
    case speech
    case safety
    case reranker
    case uncategorized

    public var id: String { rawValue }

    public var displayName: String {
        switch self {
        case .general: return "General purpose"
        case .coding: return "Coding"
        case .reasoning: return "Reasoning"
        case .vision: return "Vision (image input)"
        case .imageGeneration: return "Image generation"
        case .embedding: return "Embedding"
        case .speech: return "Speech"
        case .safety: return "Safety & policy judge"
        case .reranker: return "Reranker"
        case .uncategorized: return "Uncategorized"
        }
    }

    /// Short label for dense layouts such as table cells.
    public var shortName: String {
        switch self {
        case .general: return "General"
        case .coding: return "Coding"
        case .reasoning: return "Reasoning"
        case .vision: return "Vision"
        case .imageGeneration: return "Image gen"
        case .embedding: return "Embedding"
        case .speech: return "Speech"
        case .safety: return "Safety / judge"
        case .reranker: return "Reranker"
        case .uncategorized: return "Uncategorized"
        }
    }

    public var symbolName: String {
        switch self {
        case .general: return "text.bubble"
        case .coding: return "chevron.left.forwardslash.chevron.right"
        case .reasoning: return "brain"
        case .vision: return "eye"
        case .imageGeneration: return "photo.artframe"
        case .embedding: return "point.3.connected.trianglepath.dotted"
        case .speech: return "waveform"
        case .safety: return "checkmark.shield"
        case .reranker: return "list.number"
        case .uncategorized: return "questionmark.circle"
        }
    }
}
