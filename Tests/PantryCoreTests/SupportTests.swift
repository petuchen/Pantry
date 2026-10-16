import XCTest
@testable import PantryCore

final class SupportTests: XCTestCase {
    func testSHA256OfKnownInputs() throws {
        let tmp = try TempDir()
        let abc = tmp.url.appendingPathComponent("abc.txt")
        try Data("abc".utf8).write(to: abc)
        XCTAssertEqual(
            try FileHasher.sha256Hex(of: abc),
            "ba7816bf8f01cfea414140de5dae2223b00361a396177a9cb410ff61f20015ad"
        )
        // Chunking must not change the result.
        XCTAssertEqual(try FileHasher.sha256Hex(of: abc, chunkSize: 1), try FileHasher.sha256Hex(of: abc))
        let empty = try tmp.file("empty.bin")
        XCTAssertEqual(
            try FileHasher.sha256Hex(of: empty),
            "e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855"
        )
    }

    func testByteFormatUsesFinderStyleUnits() {
        XCTAssertTrue(ByteFormat.string(4_700_000_000).contains("GB"))
        XCTAssertTrue(ByteFormat.string(512_000_000).contains("MB"))
    }

    func testDirectorySizeIgnoresSymlinks() throws {
        let tmp = try TempDir()
        let real = try tmp.file("real/blob", bytes: 100)
        try tmp.directory("dir")
        try FileManager.default.createSymbolicLink(atPath: tmp.url.appendingPathComponent("dir/link").path, withDestinationPath: real.path)
        try tmp.file("dir/plain", bytes: 7)
        XCTAssertEqual(FileSizing.directorySize(at: tmp.url.appendingPathComponent("dir")), 7)
        XCTAssertNil(FileSizing.regularFileSize(at: tmp.url.appendingPathComponent("dir/link")))
        XCTAssertEqual(FileSizing.regularFileSize(at: real), 100)
    }

    func testDiskSpaceReportsSomethingForARealFolder() throws {
        let tmp = try TempDir()
        XCTAssertNotNil(DiskSpace.availableBytes(at: tmp.url))
        XCTAssertNotNil(DiskSpace.totalBytes(at: tmp.url))
    }

    func testModelEntrySummaryAndDecodedCategories() {
        let entry = ModelEntry(
            id: "x", service: .ollama, name: "x", sizeBytes: 1, revealURL: URL(fileURLWithPath: "/x"),
            format: .gguf, parameterSize: "8B", quantization: "Q4_K_M"
        )
        XCTAssertEqual(entry.technicalSummary, "8B · Q4_K_M · GGUF")
        XCTAssertEqual(ModelCategory.allCases.count, Set(ModelCategory.allCases.map { $0.displayName }).count, "display names are unique")
        XCTAssertEqual(ModelService.allCases.count, 4)
    }
}
