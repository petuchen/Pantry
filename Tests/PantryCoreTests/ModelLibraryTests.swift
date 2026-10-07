import XCTest
@testable import PantryCore

final class ModelLibraryTests: XCTestCase {
    func testScansEverySourceAndSortsLargestFirst() async throws {
        let tmp = try TempDir()
        let ollama = try tmp.directory("ollama")
        let hub = try tmp.directory("hub")
        let llama = try tmp.directory("llama")
        try Fixtures.ollamaModel(root: ollama, name: "small", tag: "latest", layers: [.model(bytes: 100)])
        try Fixtures.huggingFaceRepo(hub: hub, repo: "mlx-community/Big-7B-4bit", files: [
            ("model.safetensors", "w1", Data(repeating: 1, count: 9_000)),
            ("config.json", "w2", Data(#"{"quantization":{"bits":4}}"#.utf8)),
        ])
        try tmp.file("llama/medium-Q4_0.gguf", bytes: 3_000)

        let locations = ScanLocations(ollamaRoot: ollama, huggingFaceHub: hub, llamaCppFolders: [llama])
        let result = await ModelLibrary.scan(locations: locations, minimumCandidateBytes: 1)

        XCTAssertEqual(result.entries.map { $0.service }, [.mlx, .llamaCpp, .ollama])
        XCTAssertTrue(result.warnings.isEmpty)
        XCTAssertEqual(result.folders.count, 3)
        XCTAssertTrue(result.folders.allSatisfy { $0.exists })
    }

    func testCustomFolderInsideADefaultFolderDoesNotListModelsTwice() async throws {
        let tmp = try TempDir()
        let llama = try tmp.directory("llama")
        try tmp.file("llama/model-Q4_0.gguf", bytes: 100)
        let locations = ScanLocations(
            ollamaRoot: tmp.url.appendingPathComponent("none"),
            huggingFaceHub: tmp.url.appendingPathComponent("none2"),
            llamaCppFolders: [llama],
            customFolders: [CustomFolder(path: llama.path, service: .llamaCpp)]
        )
        let result = await ModelLibrary.scan(locations: locations)
        XCTAssertEqual(result.entries.count, 1)
        XCTAssertEqual(result.folders.filter { !$0.exists }.count, 2)
    }

    func testCustomFolderThatIsAHuggingFaceCacheUsesTheCacheScanner() async throws {
        let tmp = try TempDir()
        let customHub = try tmp.directory("external-hub")
        try Fixtures.huggingFaceRepo(hub: customHub, repo: "org/model-7b", files: [("model.safetensors", "z1", Data(repeating: 1, count: 100))])
        let locations = ScanLocations(
            ollamaRoot: tmp.url.appendingPathComponent("none"),
            huggingFaceHub: tmp.url.appendingPathComponent("none2"),
            llamaCppFolders: [],
            customFolders: [CustomFolder(path: customHub.path, service: .huggingFace)]
        )
        let result = await ModelLibrary.scan(locations: locations)
        XCTAssertEqual(result.entries.map { $0.name }, ["org/model-7b"])
    }

    func testDefaultLocationsFollowEnvironmentVariables() {
        let home = URL(fileURLWithPath: "/Users/test", isDirectory: true)
        let plain = ScanLocations.defaults(environment: [:], home: home)
        XCTAssertEqual(plain.ollamaRoot.path, "/Users/test/.ollama/models")
        XCTAssertEqual(plain.huggingFaceHub.path, "/Users/test/.cache/huggingface/hub")
        XCTAssertEqual(plain.llamaCppFolders.map { $0.path }, ["/Users/test/Library/Caches/llama.cpp"])

        let custom = ScanLocations.defaults(
            environment: ["OLLAMA_MODELS": "/Volumes/Fast/ollama", "HF_HOME": "/Volumes/Fast/hf", "LLAMA_CACHE": "/Volumes/Fast/llama"],
            home: home
        )
        XCTAssertEqual(custom.ollamaRoot.path, "/Volumes/Fast/ollama")
        XCTAssertEqual(custom.huggingFaceHub.path, "/Volumes/Fast/hf/hub")
        XCTAssertEqual(custom.llamaCppFolders.map { $0.path }, ["/Volumes/Fast/llama"])

        let explicit = ScanLocations.defaults(environment: ["HF_HUB_CACHE": "/x/hub", "HF_HOME": "/ignored"], home: home)
        XCTAssertEqual(explicit.huggingFaceHub.path, "/x/hub")
    }
}
