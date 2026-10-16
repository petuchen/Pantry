import XCTest
@testable import PantryCore

final class DuplicateDetectorTests: XCTestCase {
    // MARK: Identical files

    func testSameWeightsInOllamaAndLlamaCppAreIdentical() throws {
        let tmp = try TempDir()
        let ollama = try tmp.directory("ollama")
        let llama = try tmp.directory("llama")
        try Fixtures.ollamaModel(root: ollama, name: "tiny", tag: "latest", layers: [.model(bytes: 1_000, fill: 7)])
        try tmp.file("llama/tiny-Q4_0.gguf", bytes: 1_000, fill: 7)

        let entries = try OllamaScanner(root: ollama).scan()
            + LooseFolderScanner(root: llama, service: .llamaCpp, minimumCandidateBytes: 1).scan()
        let groups = DuplicateDetector().findIdentical(in: entries)

        XCTAssertEqual(groups.count, 1)
        XCTAssertEqual(groups[0].kind, .identical)
        XCTAssertEqual(Set(groups[0].entries.map { $0.service }), [.ollama, .llamaCpp])
        XCTAssertEqual(groups[0].reclaimableBytes, 1_000)
    }

    func testSameSizeButDifferentContentIsNotADuplicate() throws {
        let tmp = try TempDir()
        let ollama = try tmp.directory("ollama")
        let llama = try tmp.directory("llama")
        try Fixtures.ollamaModel(root: ollama, name: "tiny", tag: "latest", layers: [.model(bytes: 1_000, fill: 7)])
        try tmp.file("llama/other-Q4_0.gguf", bytes: 1_000, fill: 8)

        let entries = try OllamaScanner(root: ollama).scan()
            + LooseFolderScanner(root: llama, service: .llamaCpp, minimumCandidateBytes: 1).scan()
        XCTAssertTrue(DuplicateDetector().findIdentical(in: entries).isEmpty)
    }

    func testTwoOllamaTagsSharingOneBlobAreNotWastedSpace() throws {
        let tmp = try TempDir()
        try Fixtures.ollamaModel(root: tmp.url, name: "m", tag: "a", layers: [.model(bytes: 500, fill: 3)])
        try Fixtures.ollamaModel(root: tmp.url, name: "m", tag: "b", layers: [.model(bytes: 500, fill: 3)])
        let entries = try OllamaScanner(root: tmp.url).scan()
        XCTAssertEqual(entries.count, 2)
        XCTAssertTrue(DuplicateDetector().findIdentical(in: entries).isEmpty)
    }

    func testOnlyFilesSharingASizeAreEverRead() throws {
        let tmp = try TempDir()
        let llama = try tmp.directory("llama")
        try tmp.file("llama/a-Q4_0.gguf", bytes: 111, fill: 1)
        try tmp.file("llama/b-Q4_0.gguf", bytes: 222, fill: 1)
        try tmp.file("llama/c-Q4_0.gguf", bytes: 333, fill: 1)
        let entries = try LooseFolderScanner(root: llama, service: .llamaCpp, minimumCandidateBytes: 1).scan()

        let counter = CallCounter()
        let detector = DuplicateDetector(hasher: { url in counter.increment(); return try FileHasher.sha256Hex(of: url) })
        XCTAssertTrue(detector.findIdentical(in: entries).isEmpty)
        XCTAssertEqual(counter.count, 0, "unique sizes must never be hashed")
    }

    func testThreeCopiesReportTwoCopiesWorthOfWaste() throws {
        let tmp = try TempDir()
        let llama = try tmp.directory("llama")
        for name in ["a", "b", "c"] { try tmp.file("llama/\(name)-Q4_0.gguf", bytes: 400, fill: 5) }
        let entries = try LooseFolderScanner(root: llama, service: .llamaCpp, minimumCandidateBytes: 1).scan()
        let groups = DuplicateDetector().findIdentical(in: entries)
        XCTAssertEqual(groups.count, 1)
        XCTAssertEqual(groups[0].entries.count, 3)
        XCTAssertEqual(groups[0].reclaimableBytes, 800)
    }

    // MARK: Similar models

    func testSameModelInDifferentRuntimesIsSimilar() {
        let entries = [
            Fixtures.entry("llama3.2:3b", service: .ollama, size: 2_000, parameterSize: "3.2B"),
            Fixtures.entry("mlx-community/Llama-3.2-3B-Instruct-4bit", service: .mlx, size: 1_800),
            Fixtures.entry("bartowski/Llama-3.2-3B-Instruct-GGUF", service: .huggingFace, size: 2_500),
            Fixtures.entry("llama3.2:1b", service: .ollama, size: 1_300, parameterSize: "1.2B"),
            Fixtures.entry("nomic-embed-text", service: .ollama, size: 270),
        ]
        let groups = DuplicateDetector.findSimilar(in: entries)
        XCTAssertEqual(groups.count, 1)
        XCTAssertEqual(groups[0].kind, .similar)
        XCTAssertEqual(Set(groups[0].entries.map { $0.name }), [
            "llama3.2:3b", "mlx-community/Llama-3.2-3B-Instruct-4bit", "bartowski/Llama-3.2-3B-Instruct-GGUF",
        ])
        XCTAssertNil(groups[0].reclaimableBytes)
        XCTAssertEqual(groups[0].entries.first?.sizeBytes, 2_500, "largest first")
    }

    func testBaseAndInstructVariantsAreNotMerged() {
        let entries = [
            Fixtures.entry("acme/Foo-7B-Base", service: .huggingFace),
            Fixtures.entry("acme/Foo-7B-Instruct", service: .huggingFace),
        ]
        XCTAssertTrue(DuplicateDetector.findSimilar(in: entries).isEmpty)
    }

    func testDifferentSizesAreNotMerged() {
        let entries = [
            Fixtures.entry("qwen2.5:7b", service: .ollama),
            Fixtures.entry("qwen2.5:32b", service: .ollama),
        ]
        XCTAssertTrue(DuplicateDetector.findSimilar(in: entries).isEmpty)
    }

    func testUnknownSizeIsNeverGuessedSimilar() {
        let entries = [
            Fixtures.entry("llama3.2:latest", service: .ollama),
            Fixtures.entry("meta-llama/Llama-3.2-3B", service: .huggingFace),
        ]
        XCTAssertTrue(DuplicateDetector.findSimilar(in: entries).isEmpty)
    }

    func testSimilarGroupExplainedByIdenticalGroupIsDropped() {
        let a = Fixtures.entry("llama3.2:3b", service: .ollama, parameterSize: "3B")
        let b = Fixtures.entry("bartowski/Llama-3.2-3B-Instruct-GGUF", service: .llamaCpp)
        let identical = DuplicateGroup(id: "identical:x", kind: .identical, entries: [a, b], reclaimableBytes: 1_000)
        XCTAssertFalse(DuplicateDetector.findSimilar(in: [a, b]).isEmpty)
        XCTAssertTrue(DuplicateDetector.findSimilar(in: [a, b], excluding: [identical]).isEmpty)
    }

    func testSimilarGroupIDsAreStableAcrossRuns() {
        let entries = [
            Fixtures.entry("llama3.2:3b", service: .ollama, parameterSize: "3B"),
            Fixtures.entry("mlx-community/Llama-3.2-3B-Instruct-4bit", service: .mlx),
        ]
        XCTAssertEqual(
            DuplicateDetector.findSimilar(in: entries).map { $0.id },
            DuplicateDetector.findSimilar(in: entries.reversed()).map { $0.id }
        )
    }
}
