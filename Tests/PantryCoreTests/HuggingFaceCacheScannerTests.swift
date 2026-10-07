import XCTest
@testable import PantryCore

final class HuggingFaceCacheScannerTests: XCTestCase {
    private let mlxConfig = #"{"architectures":["LlamaForCausalLM"],"quantization":{"group_size":64,"bits":4}}"#

    func testMLXRepoIsAttributedToMLXAndSizedFromBlobsOnly() throws {
        let tmp = try TempDir()
        let weights = Data(repeating: 3, count: 2_000)
        let config = Data(mlxConfig.utf8)
        try Fixtures.huggingFaceRepo(hub: tmp.url, repo: "mlx-community/Llama-3.2-3B-Instruct-4bit", files: [
            ("model.safetensors", "aaa", weights),
            ("config.json", "bbb", config),
        ])

        let entries = try HuggingFaceCacheScanner(hubRoot: tmp.url, minimumCandidateBytes: 1).scan()
        let entry = try XCTUnwrap(entries.first)

        XCTAssertEqual(entries.count, 1)
        XCTAssertEqual(entry.service, .mlx)
        XCTAssertEqual(entry.name, "mlx-community/Llama-3.2-3B-Instruct-4bit")
        XCTAssertEqual(entry.sizeBytes, Int64(weights.count + config.count)) // symlinks are not double counted
        XCTAssertEqual(entry.exclusiveBytes, entry.sizeBytes)
        XCTAssertEqual(entry.format, .safetensors)
        XCTAssertEqual(entry.quantization, "4-bit")
        XCTAssertEqual(entry.parameterSize, "3B")
        XCTAssertEqual(entry.category, .general)
        XCTAssertEqual(entry.files.count, 1)
        XCTAssertEqual(entry.files.first?.size, Int64(weights.count))
        XCTAssertEqual(entry.exclusivePaths.count, 1)
        XCTAssertTrue(entry.exclusivePaths[0].lastPathComponent.hasPrefix("models--"))
    }

    func testPlainRepoIsHuggingFaceAndDatasetsAreIgnored() throws {
        let tmp = try TempDir()
        try Fixtures.huggingFaceRepo(hub: tmp.url, repo: "meta-llama/Llama-3.2-1B", files: [
            ("model.safetensors", "ccc", Data(repeating: 1, count: 500)),
            ("config.json", "ddd", Data(#"{"architectures":["LlamaForCausalLM"]}"#.utf8)),
        ])
        try tmp.directory("datasets--some--data/blobs")
        try tmp.file("datasets--some--data/blobs/x", bytes: 999)

        let entries = try HuggingFaceCacheScanner(hubRoot: tmp.url, minimumCandidateBytes: 1).scan()
        XCTAssertEqual(entries.map { $0.service }, [.huggingFace])
    }

    func testIncompleteDownloadIsFlagged() throws {
        let tmp = try TempDir()
        let repoDir = try Fixtures.huggingFaceRepo(
            hub: tmp.url, repo: "org/big-model",
            files: [("config.json", "eee", Data("{}".utf8))],
            extraBlobs: [("fff.incomplete", 4_000)]
        )
        XCTAssertTrue(FileManager.default.fileExists(atPath: repoDir.path))
        let entry = try XCTUnwrap(try HuggingFaceCacheScanner(hubRoot: tmp.url, minimumCandidateBytes: 1).scan().first)
        XCTAssertTrue(entry.isIncomplete)
    }

    func testGGUFRepoDetectsFormatAndSingleFileQuantization() throws {
        let tmp = try TempDir()
        try Fixtures.huggingFaceRepo(hub: tmp.url, repo: "bartowski/Llama-3.2-3B-Instruct-GGUF", files: [
            ("Llama-3.2-3B-Instruct-Q4_K_M.gguf", "g1", Data(repeating: 5, count: 800)),
        ])
        let entry = try XCTUnwrap(try HuggingFaceCacheScanner(hubRoot: tmp.url, minimumCandidateBytes: 1).scan().first)
        XCTAssertEqual(entry.format, .gguf)
        XCTAssertEqual(entry.quantization, "Q4_K_M")
        XCTAssertEqual(entry.service, .huggingFace)
    }

    func testModelCardPipelineTagDrivesCategory() throws {
        let tmp = try TempDir()
        try Fixtures.huggingFaceRepo(hub: tmp.url, repo: "someorg/some-model", files: [
            ("model.safetensors", "h1", Data(repeating: 2, count: 300)),
            ("README.md", "h2", Data("---\nlicense: mit\npipeline_tag: automatic-speech-recognition\n---\n# Card".utf8)),
        ])
        let entry = try XCTUnwrap(try HuggingFaceCacheScanner(hubRoot: tmp.url, minimumCandidateBytes: 1).scan().first)
        XCTAssertEqual(entry.category, .speech)
    }

    func testDiffusersRepoIsImageGeneration() throws {
        let tmp = try TempDir()
        try Fixtures.huggingFaceRepo(hub: tmp.url, repo: "someorg/pretty-pictures", files: [
            ("model_index.json", "i1", Data("{}".utf8)),
            ("unet/diffusion_pytorch_model.safetensors", "i2", Data(repeating: 4, count: 400)),
        ])
        let entry = try XCTUnwrap(try HuggingFaceCacheScanner(hubRoot: tmp.url, minimumCandidateBytes: 1).scan().first)
        XCTAssertEqual(entry.format, .diffusers)
        XCTAssertEqual(entry.category, .imageGeneration)
    }

    func testRepoIDFromFolderName() {
        XCTAssertEqual(HuggingFaceCacheScanner.repoID(fromFolderName: "models--mlx-community--Qwen2.5-7B-4bit"), "mlx-community/Qwen2.5-7B-4bit")
        XCTAssertEqual(HuggingFaceCacheScanner.repoID(fromFolderName: "models--gpt2"), "gpt2")
    }

    func testEmptyRepoFoldersAreSkipped() throws {
        let tmp = try TempDir()
        try tmp.directory("models--org--empty/blobs")
        XCTAssertTrue(try HuggingFaceCacheScanner(hubRoot: tmp.url).scan().isEmpty)
    }
}
