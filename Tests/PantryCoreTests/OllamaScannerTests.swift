import XCTest
@testable import PantryCore

final class OllamaScannerTests: XCTestCase {
    func testReadsNameSizeQuantizationAndBlobs() throws {
        let tmp = try TempDir()
        let digests = try Fixtures.ollamaModel(
            root: tmp.url, name: "llama3.2", tag: "3b",
            layers: [.model(bytes: 1_000), .template()]
        )
        XCTAssertEqual(digests.count, 3) // config + model + template

        let entries = try OllamaScanner(root: tmp.url).scan()
        XCTAssertEqual(entries.count, 1)
        let entry = try XCTUnwrap(entries.first)

        XCTAssertEqual(entry.name, "llama3.2:3b")
        XCTAssertEqual(entry.service, .ollama)
        XCTAssertEqual(entry.parameterSize, "3.2B")
        XCTAssertEqual(entry.quantization, "Q4_K_M")
        XCTAssertEqual(entry.category, .general)
        XCTAssertEqual(entry.format, .gguf)
        XCTAssertFalse(entry.isIncomplete)
        XCTAssertEqual(entry.blobs.count, 3)
        XCTAssertEqual(entry.files.count, 1)
        XCTAssertEqual(entry.files.first?.size, 1_000)
        XCTAssertNotNil(entry.files.first?.knownSHA256)
        XCTAssertTrue(entry.id.hasPrefix("ollama:"))

        let expectedBlobBytes = entry.blobs.reduce(Int64(0)) { $0 + $1.size }
        XCTAssertEqual(entry.sizeBytes, expectedBlobBytes + entry.exclusiveBytes)
        XCTAssertEqual(entry.exclusivePaths.count, 1)
        XCTAssertEqual(entry.exclusivePaths.first?.lastPathComponent, "3b")
    }

    func testProjectorLayerMeansVision() throws {
        let tmp = try TempDir()
        try Fixtures.ollamaModel(root: tmp.url, name: "mystery", tag: "latest", layers: [.model(bytes: 500), .projector(bytes: 100)])
        let entry = try XCTUnwrap(try OllamaScanner(root: tmp.url).scan().first)
        XCTAssertEqual(entry.category, .vision)
    }

    func testMissingBlobMarksModelIncomplete() throws {
        let tmp = try TempDir()
        let digests = try Fixtures.ollamaModel(root: tmp.url, name: "partial", tag: "latest", layers: [.model(bytes: 500), .template()])
        // Simulate an interrupted pull: the weights blob never finished.
        try FileManager.default.removeItem(at: tmp.url.appendingPathComponent("blobs/sha256-" + digests[1]))
        let entry = try XCTUnwrap(try OllamaScanner(root: tmp.url).scan().first)
        XCTAssertTrue(entry.isIncomplete)
        XCTAssertTrue(entry.files.isEmpty)
    }

    func testCommunityNamespaceAndOtherHostsKeepTheirPrefix() throws {
        let tmp = try TempDir()
        try Fixtures.ollamaModel(root: tmp.url, namespace: "someone", name: "custom", tag: "latest", layers: [.model(bytes: 10)])
        try Fixtures.ollamaModel(root: tmp.url, host: "example.com", namespace: "team", name: "tuned", tag: "v2", layers: [.model(bytes: 20)])
        let names = Set(try OllamaScanner(root: tmp.url).scan().map { $0.name })
        XCTAssertEqual(names, ["someone/custom:latest", "example.com/team/tuned:v2"])
    }

    func testMissingFolderIsNotAnError() throws {
        let tmp = try TempDir()
        let entries = try OllamaScanner(root: tmp.url.appendingPathComponent("does-not-exist")).scan()
        XCTAssertTrue(entries.isEmpty)
    }

    func testCorruptManifestIsSkippedNotFatal() throws {
        let tmp = try TempDir()
        try Fixtures.ollamaModel(root: tmp.url, name: "good", tag: "latest", layers: [.model(bytes: 10)])
        try tmp.file("manifests/registry.ollama.ai/library/bad/latest", text: "{ not json")
        let entries = try OllamaScanner(root: tmp.url).scan()
        XCTAssertEqual(entries.map { $0.name }, ["good:latest"])
    }

    func testDisplayNameAndDigestHelpers() {
        XCTAssertEqual(OllamaScanner.displayName(host: "registry.ollama.ai", namespace: "library", name: "llama3", tag: "8b"), "llama3:8b")
        XCTAssertEqual(OllamaScanner.hex(fromDigest: "sha256:abc123"), "abc123")
        XCTAssertEqual(OllamaScanner.hex(fromDigest: "sha256-abc123"), "abc123")
    }
}
