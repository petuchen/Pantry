import XCTest
@testable import PantryCore

final class LooseFolderScannerTests: XCTestCase {
    func testFindsGGUFFilesAndParsesQuantization() throws {
        let tmp = try TempDir()
        try tmp.file("Meta-Llama-3.1-8B-Instruct-Q4_K_M.gguf", bytes: 1_000)
        try tmp.file("nested/deeper/qwen2.5-coder-7b-instruct-q8_0.gguf", bytes: 2_000)
        try tmp.file("notes.txt", bytes: 10)

        let entries = try LooseFolderScanner(root: tmp.url, service: .llamaCpp, minimumCandidateBytes: 1).scan()
        let byName = Dictionary(uniqueKeysWithValues: entries.map { ($0.name, $0) })

        XCTAssertEqual(entries.count, 2)
        let llama = try XCTUnwrap(byName["Meta-Llama-3.1-8B-Instruct-Q4_K_M"])
        XCTAssertEqual(llama.quantization, "Q4_K_M")
        XCTAssertEqual(llama.parameterSize, "8B")
        XCTAssertEqual(llama.category, .general)
        XCTAssertEqual(llama.sizeBytes, 1_000)
        XCTAssertEqual(llama.service, .llamaCpp)
        let coder = try XCTUnwrap(byName["qwen2.5-coder-7b-instruct-q8_0"])
        XCTAssertEqual(coder.category, .coding)
        XCTAssertEqual(coder.quantization, "Q8_0")
    }

    func testShardedGGUFIsOneModel() throws {
        let tmp = try TempDir()
        try tmp.file("big-00001-of-00002.gguf", bytes: 600)
        try tmp.file("big-00002-of-00002.gguf", bytes: 400)
        let entries = try LooseFolderScanner(root: tmp.url, service: .llamaCpp, minimumCandidateBytes: 1).scan()
        XCTAssertEqual(entries.count, 1)
        XCTAssertEqual(entries[0].name, "big")
        XCTAssertEqual(entries[0].sizeBytes, 1_000)
        XCTAssertEqual(entries[0].exclusivePaths.count, 2)
    }

    func testCacheMetadataSidecarsAreRemovedWithTheModel() throws {
        let tmp = try TempDir()
        try tmp.file("model-Q4_0.gguf", bytes: 1_000)
        try tmp.file("model-Q4_0.gguf.json", bytes: 50)
        let entry = try XCTUnwrap(try LooseFolderScanner(root: tmp.url, service: .llamaCpp).scan().first)
        XCTAssertEqual(entry.exclusivePaths.map { $0.lastPathComponent }.sorted(), ["model-Q4_0.gguf", "model-Q4_0.gguf.json"])
        XCTAssertEqual(entry.exclusiveBytes, 1_050)
        XCTAssertEqual(entry.sizeBytes, 1_000) // the model itself; metadata is bookkeeping
    }

    func testLlamaCppCachePrefixIsHiddenFromTheName() {
        XCTAssertEqual(
            LooseFolderScanner.cleanGGUFName("bartowski_Llama-3.2-3B-Instruct-GGUF_Llama-3.2-3B-Instruct-Q4_K_M"),
            "Llama-3.2-3B-Instruct-Q4_K_M"
        )
        XCTAssertEqual(LooseFolderScanner.cleanGGUFName("plain-model"), "plain-model")
    }

    func testSafetensorsDirectoryIsOneModelAndNotDescendedInto() throws {
        let tmp = try TempDir()
        try tmp.file("whisper-large-v3/config.json", text: "{}")
        try tmp.file("whisper-large-v3/model.safetensors", bytes: 700)
        try tmp.file("whisper-large-v3/extra/readme.txt", bytes: 30)

        let entries = try LooseFolderScanner(root: tmp.url, service: .mlx, minimumCandidateBytes: 1).scan()
        XCTAssertEqual(entries.count, 1)
        XCTAssertEqual(entries[0].name, "whisper-large-v3")
        XCTAssertEqual(entries[0].format, .safetensors)
        XCTAssertEqual(entries[0].category, .speech)
        XCTAssertEqual(entries[0].sizeBytes, 732) // 700 weights + 2 config + 30 readme
        XCTAssertEqual(entries[0].service, .mlx)
    }

    func testMissingRootIsNotAnError() throws {
        let tmp = try TempDir()
        XCTAssertTrue(try LooseFolderScanner(root: tmp.url.appendingPathComponent("nope"), service: .llamaCpp).scan().isEmpty)
    }
}
