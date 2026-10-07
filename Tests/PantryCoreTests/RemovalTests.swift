import XCTest
@testable import PantryCore

final class RemovalPlannerTests: XCTestCase {
    private func twoTagsSharingWeights() throws -> (TempDir, [ModelEntry]) {
        let tmp = try TempDir()
        try Fixtures.ollamaModel(root: tmp.url, name: "m", tag: "a", layers: [.model(bytes: 1_000, fill: 4), .template("A")])
        try Fixtures.ollamaModel(root: tmp.url, name: "m", tag: "b", layers: [.model(bytes: 1_000, fill: 4), .template("B")])
        let entries = try OllamaScanner(root: tmp.url).scan().sorted { $0.name < $1.name }
        return (tmp, entries)
    }

    func testRemovingOneTagKeepsTheSharedWeights() throws {
        let (_, entries) = try twoTagsSharingWeights()
        let plan = RemovalPlanner.plan(removing: [entries[0]], from: entries)

        XCTAssertEqual(plan.keptBlobs.count, 2) // shared weights + shared config
        XCTAssertTrue(plan.keptBlobs.contains { $0.bytes == 1_000 && $0.stillUsedBy == ["m:b"] })
        XCTAssertFalse(plan.paths.contains { $0.bytes == 1_000 })
        XCTAssertLessThan(plan.reclaimableBytes, 1_000)
        XCTAssertTrue(plan.paths.contains { $0.url.lastPathComponent == "a" }, "the manifest is removed")
    }

    func testRemovingBothTagsFreesTheSharedWeightsOnce() throws {
        let (_, entries) = try twoTagsSharingWeights()
        let plan = RemovalPlanner.plan(removing: entries, from: entries)

        XCTAssertTrue(plan.keptBlobs.isEmpty)
        XCTAssertEqual(plan.paths.filter { $0.bytes == 1_000 }.count, 1)
        XCTAssertEqual(plan.reclaimableBytes, StorageSummary.physicalBytes(of: entries))
    }

    func testManifestsComeBeforeBlobs() throws {
        let (_, entries) = try twoTagsSharingWeights()
        let plan = RemovalPlanner.plan(removing: entries, from: entries)
        let firstBlob = plan.paths.firstIndex { $0.url.lastPathComponent.hasPrefix("sha256-") }
        let lastManifest = plan.paths.lastIndex { !$0.url.lastPathComponent.hasPrefix("sha256-") }
        XCTAssertNotNil(firstBlob)
        XCTAssertNotNil(lastManifest)
        XCTAssertLessThan(lastManifest!, firstBlob!)
    }

    func testHuggingFaceRepoRemovesTheWholeFolder() throws {
        let tmp = try TempDir()
        try Fixtures.huggingFaceRepo(hub: tmp.url, repo: "org/model-7b", files: [("model.safetensors", "w", Data(repeating: 1, count: 100))])
        let entries = try HuggingFaceCacheScanner(hubRoot: tmp.url, minimumCandidateBytes: 1).scan()
        let plan = RemovalPlanner.plan(removing: entries, from: entries)
        XCTAssertEqual(plan.paths.count, 1)
        XCTAssertEqual(plan.reclaimableBytes, 100)
    }
}

final class RemovalExecutorTests: XCTestCase {
    func testPermanentDeleteRemovesModelAndPrunesEmptyManifestFolders() throws {
        let tmp = try TempDir()
        try Fixtures.ollamaModel(root: tmp.url, name: "gone", tag: "latest", layers: [.model(bytes: 500, fill: 6)])
        let keep = try Fixtures.ollamaModel(root: tmp.url, name: "stay", tag: "latest", layers: [.model(bytes: 700, fill: 9)])
        let entries = try OllamaScanner(root: tmp.url).scan()
        let gone = try XCTUnwrap(entries.first { $0.name == "gone:latest" })

        let plan = RemovalPlanner.plan(removing: [gone], from: entries)
        let result = RemovalExecutor(allowedRoots: [tmp.url]).execute(plan, mode: .deletePermanently)

        XCTAssertTrue(result.isCompleteSuccess)
        XCTAssertFalse(tmp.exists("manifests/registry.ollama.ai/library/gone"), "empty name folder is pruned")
        XCTAssertTrue(tmp.exists("manifests/registry.ollama.ai/library/stay/latest"))
        XCTAssertTrue(tmp.exists("manifests"), "the manifests root itself is never pruned")
        XCTAssertTrue(tmp.exists("blobs/sha256-" + keep[1]), "other models' weights are untouched")
        XCTAssertGreaterThan(result.bytesRemoved, 0)
        let after = try OllamaScanner(root: tmp.url).scan()
        XCTAssertEqual(after.map { $0.name }, ["stay:latest"])
    }

    func testHuggingFaceRepoIsRemovedWithoutTouchingSymlinkTargetsOutsideIt() throws {
        let tmp = try TempDir()
        let hub = try tmp.directory("hub")
        let outside = try tmp.file("outside/precious.bin", bytes: 10)
        let repoDir = try Fixtures.huggingFaceRepo(hub: hub, repo: "org/m", files: [("w.safetensors", "w1", Data(repeating: 1, count: 50))])
        // A rogue symlink inside the repo pointing at an unrelated file.
        try FileManager.default.createSymbolicLink(atPath: repoDir.appendingPathComponent("snapshots/abc123/evil").path, withDestinationPath: outside.path)

        let entries = try HuggingFaceCacheScanner(hubRoot: hub, minimumCandidateBytes: 1).scan()
        let result = RemovalExecutor(allowedRoots: [hub]).execute(RemovalPlanner.plan(removing: entries, from: entries), mode: .deletePermanently)

        XCTAssertTrue(result.isCompleteSuccess)
        XCTAssertFalse(FileManager.default.fileExists(atPath: repoDir.path))
        XCTAssertTrue(FileManager.default.fileExists(atPath: outside.path), "symlinks are removed, never followed")
    }

    func testRefusesPathsOutsideKnownFoldersAndRemovesNothing() throws {
        let tmp = try TempDir()
        let managed = try tmp.directory("managed")
        let inside = try tmp.file("managed/ok.gguf", bytes: 10)
        let outside = try tmp.file("elsewhere/important.txt", bytes: 10)
        let plan = RemovalPlan(
            entries: [],
            paths: [PlannedPath(url: inside, bytes: 10), PlannedPath(url: outside, bytes: 10)],
            reclaimableBytes: 20, keptBlobs: []
        )
        let result = RemovalExecutor(allowedRoots: [managed]).execute(plan, mode: .deletePermanently)

        XCTAssertFalse(result.isCompleteSuccess)
        XCTAssertEqual(result.failures.map { $0.path }, [outside.path])
        XCTAssertTrue(FileManager.default.fileExists(atPath: inside.path), "all-or-nothing: even the safe file stays")
        XCTAssertTrue(FileManager.default.fileExists(atPath: outside.path))
        XCTAssertEqual(result.bytesRemoved, 0)
    }

    func testRefusesToRemoveAManagedRootItself() throws {
        let tmp = try TempDir()
        let managed = try tmp.directory("managed")
        let plan = RemovalPlan(entries: [], paths: [PlannedPath(url: managed, bytes: 0)], reclaimableBytes: 0, keptBlobs: [])
        let result = RemovalExecutor(allowedRoots: [managed]).execute(plan, mode: .deletePermanently)
        XCTAssertFalse(result.isCompleteSuccess)
        XCTAssertTrue(FileManager.default.fileExists(atPath: managed.path))
    }

    func testAlreadyMissingFilesAreNotFailures() throws {
        let tmp = try TempDir()
        let managed = try tmp.directory("managed")
        let ghost = managed.appendingPathComponent("ghost.gguf")
        let plan = RemovalPlan(entries: [], paths: [PlannedPath(url: ghost, bytes: 5)], reclaimableBytes: 5, keptBlobs: [])
        let result = RemovalExecutor(allowedRoots: [managed]).execute(plan, mode: .deletePermanently)
        XCTAssertTrue(result.isCompleteSuccess)
    }
}

final class PathSafetyTests: XCTestCase {
    func testStrictlyInside() throws {
        let tmp = try TempDir()
        let root = try tmp.directory("root")
        XCTAssertTrue(PathSafety.isStrictlyInside(root.appendingPathComponent("a/b.gguf"), root: root))
        XCTAssertFalse(PathSafety.isStrictlyInside(root, root: root))
        XCTAssertFalse(PathSafety.isStrictlyInside(tmp.url.appendingPathComponent("rootsibling/x"), root: root), "prefix match must be by component")
        XCTAssertFalse(PathSafety.isStrictlyInside(root.appendingPathComponent("../outside"), root: root), "dot-dot is normalised")
    }

    func testSymlinkedParentThatEscapesTheRootIsRejected() throws {
        let tmp = try TempDir()
        let root = try tmp.directory("root")
        let outside = try tmp.directory("outside")
        try FileManager.default.createSymbolicLink(atPath: root.appendingPathComponent("link").path, withDestinationPath: outside.path)
        XCTAssertFalse(PathSafety.isStrictlyInside(root.appendingPathComponent("link/file"), root: root))
        // The link itself is fine to remove: removing it never touches its target.
        XCTAssertTrue(PathSafety.isStrictlyInside(root.appendingPathComponent("link"), root: root))
    }

    func testRelativeComponents() throws {
        let tmp = try TempDir()
        let root = try tmp.directory("root")
        XCTAssertEqual(PathSafety.relativeComponents(of: root.appendingPathComponent("a/b/c"), under: root), ["a", "b", "c"])
        XCTAssertNil(PathSafety.relativeComponents(of: tmp.url, under: root))
    }
}
