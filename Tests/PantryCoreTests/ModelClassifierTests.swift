import XCTest
@testable import PantryCore

final class ModelClassifierTests: XCTestCase {
    func testNameBasedCategories() {
        let expectations: [(String, ModelCategory)] = [
            ("llama3.2:3b", .general),
            ("mistral:7b", .general),
            ("gemma3:4b", .general),
            ("phi4:14b", .general),
            ("unsloth/gpt-oss-20b-GGUF", .general),
            ("hf.co/bartowski/Llama-3.2-3B-Instruct-GGUF:Q4_K_M", .general),
            ("llama3.2-vision:11b", .vision),
            ("llava:13b", .vision),
            ("Qwen/Qwen2.5-VL-7B-Instruct", .vision),
            ("mlx-community/Qwen3-VL-8B-Instruct-4bit", .vision),
            ("deepseek-ocr", .vision),
            ("qwen2.5-coder:7b", .coding),
            ("codestral:22b", .coding),
            ("starcoder2:3b", .coding),
            ("devstral:24b", .coding),
            ("Qwen3-Coder-30B-A3B-Instruct", .coding),
            ("deepseek-r1:7b", .reasoning),
            ("qwq:32b", .reasoning),
            ("magistral:24b", .reasoning),
            ("openthinker:7b", .reasoning),
            ("llama-guard3:1b", .safety),
            ("shieldgemma:2b", .safety),
            ("granite3-guardian:2b", .safety),
            ("nvidia/Llama-3.1-Nemotron-70B-Reward", .safety),
            ("nomic-embed-text", .embedding),
            ("bge-m3", .embedding),
            ("mxbai-embed-large", .embedding),
            ("snowflake-arctic-embed:335m", .embedding),
            ("BAAI/bge-reranker-v2-m3", .reranker),
            ("mlx-community/whisper-large-v3-mlx", .speech),
            ("mlx-community/Kokoro-82M-bf16", .speech),
            ("black-forest-labs/FLUX.1-dev", .imageGeneration),
            ("stabilityai/stable-diffusion-xl-base-1.0", .imageGeneration),
            ("some-random-thing", .uncategorized),
        ]
        for (name, expected) in expectations {
            XCTAssertEqual(ModelClassifier.classify(name: name), expected, name)
        }
    }

    func testMetadataHintsWhenTheNameSaysNothing() {
        XCTAssertEqual(ModelClassifier.classify(name: "mystery", hints: ClassificationHints(hasProjector: true)), .vision)
        XCTAssertEqual(ModelClassifier.classify(name: "mystery", hints: ClassificationHints(isDiffusers: true)), .imageGeneration)
        XCTAssertEqual(ModelClassifier.classify(name: "mystery", hints: ClassificationHints(families: ["nomic-bert"])), .embedding)
        XCTAssertEqual(ModelClassifier.classify(name: "mystery", hints: ClassificationHints(architectures: ["Qwen2VLForConditionalGeneration"])), .vision)
        XCTAssertEqual(ModelClassifier.classify(name: "mystery", hints: ClassificationHints(architectures: ["LlamaForCausalLM"])), .general)
    }

    func testPipelineTagBeatsNameButTextGenerationDoesNot() {
        XCTAssertEqual(ModelClassifier.classify(name: "org/model", hints: ClassificationHints(pipelineTag: "automatic-speech-recognition")), .speech)
        XCTAssertEqual(ModelClassifier.classify(name: "org/model", hints: ClassificationHints(pipelineTag: "text-ranking")), .reranker)
        XCTAssertEqual(ModelClassifier.classify(name: "org/coder-model", hints: ClassificationHints(pipelineTag: "text-generation")), .coding)
    }

    func testNameRuleWinsOverWeakerMetadata() {
        // A guard model with a causal-LM architecture is still a guard model.
        let hints = ClassificationHints(architectures: ["LlamaForCausalLM"])
        XCTAssertEqual(ModelClassifier.classify(name: "meta-llama/Llama-Guard-3-8B", hints: hints), .safety)
    }
}
