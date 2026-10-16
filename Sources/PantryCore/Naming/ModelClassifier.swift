import Foundation

/// Extra evidence gathered by a scanner (config files, model-card front matter, Ollama layers).
public struct ClassificationHints: Sendable {
    public var families: [String]
    public var architectures: [String]
    public var hasProjector: Bool
    public var isDiffusers: Bool
    /// Hugging Face `pipeline_tag` from a model card, e.g. "automatic-speech-recognition".
    public var pipelineTag: String?

    public init(
        families: [String] = [],
        architectures: [String] = [],
        hasProjector: Bool = false,
        isDiffusers: Bool = false,
        pipelineTag: String? = nil
    ) {
        self.families = families
        self.architectures = architectures
        self.hasProjector = hasProjector
        self.isDiffusers = isDiffusers
        self.pipelineTag = pipelineTag
    }
}

/// Heuristic "what is this model for" classifier. Order matters: more specific
/// purposes (guard, embedding, vision, coder) are tested before the broad "general" families.
public enum ModelClassifier {
    private static func regex(_ pattern: String) -> NSRegularExpression {
        return try! NSRegularExpression(pattern: pattern, options: [])
    }

    private static let nameRules: [(ModelCategory, NSRegularExpression)] = [
        (.imageGeneration, regex(#"stable-?diffusion|sdxl|(?<![a-z0-9])sd-?3|(?<![a-z0-9])flux|qwen-?image|kandinsky|pixart|dreamshaper|stable-?cascade|hunyuan-?dit|z-image|text-to-image"#)),
        (.safety, regex(#"llama-?guard|shieldgemma|guardian|wildguard|nemoguard|prompt-?guard|safeguard|polyguard|content-?safety|(?<![a-z0-9])guard(?![a-z0-9])|(?<![a-z0-9])judge(?![a-z0-9])|prometheus|reward|(?<![a-z0-9])rm(?![a-z0-9])|moderation|toxic"#)),
        (.reranker, regex(#"rerank"#)),
        (.embedding, regex(#"embed|(?<![a-z0-9])(?:bge|gte|e5)(?![a-z0-9])|minilm|mxbai|bert|colbert|sentence-transformers|sbert"#)),
        (.speech, regex(#"whisper|parakeet|wav2vec|hubert|(?<![a-z0-9])tts(?![a-z0-9])|kokoro|speecht5|canary|moonshine|orpheus|xtts|f5-?tts|voxtral|ultravox|(?<![a-z0-9])asr(?![a-z0-9])|(?<![a-z0-9])bark|musicgen|audio|speech|parler"#)),
        (.vision, regex(#"llava|vision|(?<![a-z])vl(?![a-z])|pixtral|moondream|minicpm-?v|paligemma|smolvlm|idefics|internvl|molmo|(?<![a-z])ocr(?![a-z])|olmocr|(?<![a-z])vlm(?![a-z])|florence"#)),
        (.coding, regex(#"coder|codellama|code-?llama|starcoder|codegemma|codestral|devstral|codeqwen|granite-?code|opencoder|(?<![a-z0-9])code(?![a-z0-9])"#)),
        (.reasoning, regex(#"deepseek-?r1|(?<![a-z0-9])r1(?![a-z0-9])|qwq|reason|(?<![a-z0-9])o1(?![a-z0-9])|thinking|magistral|openthinker|(?<![a-z0-9])cot(?![a-z0-9])|exaone-deep"#)),
        (.general, regex(#"llama|qwen|gemma|mistral|mixtral|phi|deepseek|falcon|(?<![a-z])yi(?![a-z])|glm|granite|smollm|olmo|command-?r|solar|internlm|nemotron|gpt-?oss|minimax|kimi|exaone|hermes|tulu|openchat|vicuna|zephyr|starling|orca|dolphin|wizardlm|instruct|chat|(?<![a-z0-9])it(?![a-z0-9])|lfm|arcee|reka"#)),
    ]

    private static let visionArchitectures = regex(#"vl|vision|llava|idefics|paligemma|mllama|pixtral|internvl|moondream|clip"#)
    private static let embeddingArchitectures = regex(#"bertmodel|xlmrobertamodel|nomicbert|modernbert|bert"#)
    private static let causalArchitectures = regex(#"causallm|lmheadmodel|forconditionalgeneration"#)

    public static func classify(name: String, hints: ClassificationHints = ClassificationHints()) -> ModelCategory {
        if hints.isDiffusers { return .imageGeneration }
        if let tag = hints.pipelineTag, let fromTag = category(forPipelineTag: tag) { return fromTag }

        let lowered = name.lowercased()
        let evidence = (hints.architectures + hints.families).joined(separator: " ").lowercased()

        for (category, pattern) in nameRules {
            if matches(pattern, lowered) { return category }
            // Metadata evidence is consulted right after the name rule of the same kind,
            // so a name match always wins over weaker config-file hints.
            switch category {
            case .embedding:
                if matches(embeddingArchitectures, evidence) { return .embedding }
            case .vision:
                if hints.hasProjector || matches(visionArchitectures, evidence) { return .vision }
            default:
                break
            }
        }
        if matches(causalArchitectures, evidence) { return .general }
        return .uncategorized
    }

    /// Maps non-text-generation HF pipeline tags to categories. Plain `text-generation` is
    /// deliberately not decisive: a coder or reasoner is also `text-generation`.
    static func category(forPipelineTag tag: String) -> ModelCategory? {
        switch tag.lowercased() {
        case "image-text-to-text", "image-to-text", "visual-question-answering", "video-text-to-text", "document-question-answering":
            return .vision
        case "text-to-image", "image-to-image", "text-to-video", "unconditional-image-generation":
            return .imageGeneration
        case "feature-extraction", "sentence-similarity":
            return .embedding
        case "automatic-speech-recognition", "text-to-speech", "text-to-audio", "audio-to-audio", "audio-classification":
            return .speech
        case "text-ranking":
            return .reranker
        default:
            return nil
        }
    }

    private static func matches(_ pattern: NSRegularExpression, _ value: String) -> Bool {
        let range = NSRange(location: 0, length: (value as NSString).length)
        return pattern.firstMatch(in: value, options: [], range: range) != nil
    }
}
