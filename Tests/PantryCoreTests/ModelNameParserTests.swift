import XCTest
@testable import PantryCore

final class ModelNameParserTests: XCTestCase {
    private func check(
        _ raw: String, key: String, billions: Double? = nil, quant: String? = nil, instruct: Bool? = nil,
        file: StaticString = #filePath, line: UInt = #line
    ) {
        let parsed = ModelNameParser.parse(raw)
        XCTAssertEqual(parsed.baseKey, key, "key for \(raw)", file: file, line: line)
        if let billions {
            XCTAssertEqual(parsed.parameterBillions ?? -1, billions, accuracy: 1e-9, "params for \(raw)", file: file, line: line)
        } else {
            XCTAssertNil(parsed.parameterBillions, "params for \(raw)", file: file, line: line)
        }
        XCTAssertEqual(parsed.quantization, quant, "quant for \(raw)", file: file, line: line)
        XCTAssertEqual(parsed.isInstruct, instruct, "instruct for \(raw)", file: file, line: line)
    }

    func testOllamaAndHuggingFaceNamesShareAKey() {
        check("llama3.2:3b", key: "llama3.2", billions: 3)
        check("meta-llama/Llama-3.2-3B-Instruct", key: "llama3.2", billions: 3, instruct: true)
        check("mlx-community/Llama-3.2-3B-Instruct-4bit", key: "llama3.2", billions: 3, quant: "4-bit", instruct: true)
        check("bartowski/Meta-Llama-3.1-8B-Instruct-GGUF", key: "llama3.1", billions: 8, instruct: true)
        check("llama3.1:8b-instruct-q4_K_M", key: "llama3.1", billions: 8, quant: "Q4_K_M", instruct: true)
        check("qwen2.5-coder:7b", key: "qwen2.5coder", billions: 7)
        check("Qwen/Qwen2.5-Coder-7B-Instruct", key: "qwen2.5coder", billions: 7, instruct: true)
        check("gemma-2-9b-it-GGUF", key: "gemma2", billions: 9, instruct: true)
        check("gemma2:9b", key: "gemma2", billions: 9)
    }

    func testQuantizationVariants() {
        check("Meta-Llama-3.1-8B-Instruct-Q4_K_M.gguf", key: "llama3.1", billions: 8, quant: "Q4_K_M", instruct: true)
        check("unsloth/Qwen3-30B-A3B-UD-Q4_K_XL.gguf", key: "qwen3", billions: 30, quant: "Q4_K_XL")
        check("mistral-7b-instruct-v0.3.Q8_0.gguf", key: "mistralv0.3", billions: 7, quant: "Q8_0", instruct: true)
        check("llama3.2:1b-instruct-fp16", key: "llama3.2", billions: 1, quant: "FP16", instruct: true)
        check("phi-4-reasoning-IQ4_XS.gguf", key: "phi4reasoning", quant: "IQ4_XS")
    }

    func testShardSuffixAndUnits() {
        check("model-00001-of-00003.gguf", key: "model")
        check("SmolLM2-360M-Instruct", key: "smollm2", billions: 0.36, instruct: true)
        check("Mixtral-8x7B-Instruct-v0.1", key: "mixtralv0.1", billions: 56, instruct: true)
    }

    func testRepeatedSizeTokenFromLlamaCppCacheNameIsIgnored() {
        // org_repo-GGUF_file keeps the size twice; only the first counts.
        let parsed = ModelNameParser.parse("Llama-3.2-3B-Instruct-3B-Q4_K_M")
        XCTAssertEqual(parsed.baseKey, "llama3.2")
    }

    func testParameterSizeHelpers() {
        XCTAssertEqual(ParameterSize.billions(from: "3.2B") ?? 0, 3.2, accuracy: 1e-9)
        XCTAssertEqual(ParameterSize.billions(from: "270M") ?? 0, 0.27, accuracy: 1e-9)
        XCTAssertEqual(ParameterSize.billions(from: "E2B") ?? 0, 2, accuracy: 1e-9)
        XCTAssertNil(ParameterSize.billions(from: "huge"))
        XCTAssertTrue(ParameterSize.areClose(3.2, 3))
        XCTAssertTrue(ParameterSize.areClose(7.6, 7))
        XCTAssertFalse(ParameterSize.areClose(3, 8))
        XCTAssertFalse(ParameterSize.areClose(1, 3))
    }
}
