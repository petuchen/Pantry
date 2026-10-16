import XCTest
@testable import PantryCore

final class StorageSummaryTests: XCTestCase {
    func testSharedBlobsAreCountedOncePhysically() throws {
        let tmp = try TempDir()
        // Two tags share the same 1000-byte weights layer.
        try Fixtures.ollamaModel(root: tmp.url, name: "m", tag: "a", layers: [.model(bytes: 1_000, fill: 4)])
        try Fixtures.ollamaModel(root: tmp.url, name: "m", tag: "b", layers: [.model(bytes: 1_000, fill: 4)])
        let entries = try OllamaScanner(root: tmp.url).scan()

        let apparent = entries.reduce(Int64(0)) { $0 + $1.sizeBytes }
        let summary = StorageSummary.make(from: entries)

        XCTAssertEqual(summary.modelCount, 2)
        XCTAssertLessThan(summary.totalBytes, apparent)
        XCTAssertEqual(summary.totalBytes, apparent - 1_000 - entries[0].blobs.first(where: { $0.size < 1_000 })!.size)
    }

    func testBreakdownByServiceAndCategory() {
        let big = ModelEntry(id: "1", service: .mlx, name: "a", sizeBytes: 9_000, revealURL: URL(fileURLWithPath: "/a"), category: .general, exclusiveBytes: 9_000)
        let mid = ModelEntry(id: "2", service: .ollama, name: "b", sizeBytes: 3_000, revealURL: URL(fileURLWithPath: "/b"), category: .coding, exclusiveBytes: 3_000)
        let small = ModelEntry(id: "3", service: .ollama, name: "c", sizeBytes: 500, revealURL: URL(fileURLWithPath: "/c"), category: .general, exclusiveBytes: 500, isIncomplete: true)
        let summary = StorageSummary.make(from: [small, big, mid])

        XCTAssertEqual(summary.totalBytes, 12_500)
        XCTAssertEqual(summary.byService.map { $0.service }, [.mlx, .ollama])
        XCTAssertEqual(summary.byService.map { $0.bytes }, [9_000, 3_500])
        XCTAssertEqual(summary.byService.last?.modelCount, 2)
        XCTAssertEqual(summary.byCategory.map { $0.category }, [.general, .coding])
        XCTAssertEqual(summary.largest.map { $0.id }, ["1", "2", "3"])
        XCTAssertEqual(summary.incompleteCount, 1)
    }

    func testEmptyLibrary() {
        let summary = StorageSummary.make(from: [])
        XCTAssertEqual(summary.totalBytes, 0)
        XCTAssertTrue(summary.byService.isEmpty)
    }
}
