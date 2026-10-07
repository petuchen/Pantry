import XCTest
@testable import PantryCore

final class ModelReferenceTests: XCTestCase {
    func testOllamaNamesAcceptWhatPeoplePaste() {
        XCTAssertEqual(ModelReference.ollamaName(from: "llama3.2:3b"), "llama3.2:3b")
        XCTAssertEqual(ModelReference.ollamaName(from: "  llama3.2  \n"), "llama3.2")
        XCTAssertEqual(ModelReference.ollamaName(from: "ollama run llama3.2:1b"), "llama3.2:1b")
        XCTAssertEqual(ModelReference.ollamaName(from: "ollama pull qwen2.5-coder:7b"), "qwen2.5-coder:7b")
        XCTAssertEqual(ModelReference.ollamaName(from: "https://ollama.com/library/gemma3:4b"), "gemma3:4b")
        XCTAssertEqual(ModelReference.ollamaName(from: "https://ollama.com/library/llama3.2/"), "llama3.2")
        XCTAssertEqual(ModelReference.ollamaName(from: "someone/custom:latest"), "someone/custom:latest")
        XCTAssertEqual(ModelReference.ollamaName(from: "hf.co/bartowski/Llama-3.2-3B-Instruct-GGUF:Q4_K_M"), "hf.co/bartowski/Llama-3.2-3B-Instruct-GGUF:Q4_K_M")
    }

    func testOllamaRejectsNonsense() {
        XCTAssertNil(ModelReference.ollamaName(from: ""))
        XCTAssertNil(ModelReference.ollamaName(from: "two words"))
        XCTAssertNil(ModelReference.ollamaName(from: "rm -rf /"))
        XCTAssertNil(ModelReference.ollamaName(from: ":3b"))
    }

    func testHuggingFaceReposAcceptURLsAndCommands() {
        XCTAssertEqual(ModelReference.huggingFaceRepo(from: "mlx-community/Qwen2.5-7B-Instruct-4bit"), "mlx-community/Qwen2.5-7B-Instruct-4bit")
        XCTAssertEqual(ModelReference.huggingFaceRepo(from: "https://huggingface.co/mlx-community/Qwen2.5-7B-Instruct-4bit"), "mlx-community/Qwen2.5-7B-Instruct-4bit")
        XCTAssertEqual(ModelReference.huggingFaceRepo(from: "https://huggingface.co/org/name/tree/main"), "org/name")
        XCTAssertEqual(ModelReference.huggingFaceRepo(from: "hf download org/name --include x"), "org/name")
        XCTAssertEqual(ModelReference.huggingFaceRepo(from: "huggingface-cli download org/name"), "org/name")
        XCTAssertEqual(ModelReference.huggingFaceRepo(from: "hf.co/bartowski/Foo-GGUF:Q4_K_M"), "bartowski/Foo-GGUF")
        XCTAssertEqual(ModelReference.huggingFaceRepo(from: "  org/name  "), "org/name")
    }

    func testHuggingFaceRejectsDatasetsSpacesAndJunk() {
        XCTAssertNil(ModelReference.huggingFaceRepo(from: "https://huggingface.co/datasets/org/data"))
        XCTAssertNil(ModelReference.huggingFaceRepo(from: "https://huggingface.co/spaces/org/app"))
        XCTAssertNil(ModelReference.huggingFaceRepo(from: "justaword"))
        XCTAssertNil(ModelReference.huggingFaceRepo(from: "a/b/c"))
        XCTAssertNil(ModelReference.huggingFaceRepo(from: ""))
    }
}

final class OllamaProgressTests: XCTestCase {
    func testAggregatesLayersIntoOneProgressValue() throws {
        var aggregator = OllamaPullProgressAggregator()
        _ = try aggregator.ingest(line: #"{"status":"pulling manifest"}"#)
        let first = try XCTUnwrap(try aggregator.ingest(line: #"{"status":"pulling aaa","digest":"sha256:aaa","total":1000,"completed":250}"#))
        XCTAssertEqual(first.phase, "Downloading")
        XCTAssertEqual(first.totalBytes, 1_000)
        XCTAssertEqual(first.completedBytes, 250)

        let second = try XCTUnwrap(try aggregator.ingest(line: #"{"status":"pulling bbb","digest":"sha256:bbb","total":3000,"completed":1000}"#))
        XCTAssertEqual(second.totalBytes, 4_000)
        XCTAssertEqual(second.completedBytes, 1_250)
        XCTAssertEqual(try XCTUnwrap(second.fraction), 0.3125, accuracy: 1e-9)

        // A later update for the first layer replaces its previous value.
        let third = try XCTUnwrap(try aggregator.ingest(line: #"{"status":"pulling aaa","digest":"sha256:aaa","total":1000,"completed":1000}"#))
        XCTAssertEqual(third.completedBytes, 2_000)
    }

    func testPhasesAndCompletion() throws {
        var aggregator = OllamaPullProgressAggregator()
        XCTAssertEqual(try aggregator.ingest(line: #"{"status":"pulling manifest"}"#)?.phase, "Fetching details")
        XCTAssertEqual(try aggregator.ingest(line: #"{"status":"verifying sha256 digest"}"#)?.phase, "Verifying")
        XCTAssertEqual(try aggregator.ingest(line: #"{"status":"writing manifest"}"#)?.phase, "Finishing up")
        XCTAssertFalse(aggregator.isFinished)
        XCTAssertEqual(try aggregator.ingest(line: #"{"status":"success"}"#)?.phase, "Done")
        XCTAssertTrue(aggregator.isFinished)
    }

    func testErrorLinesThrowTheServersMessage() {
        var aggregator = OllamaPullProgressAggregator()
        XCTAssertThrowsError(try aggregator.ingest(line: #"{"error":"pull model manifest: file does not exist"}"#)) { error in
            XCTAssertEqual(error as? DownloadError, .remote("pull model manifest: file does not exist"))
        }
    }

    func testGarbageLinesAreIgnored() throws {
        var aggregator = OllamaPullProgressAggregator()
        XCTAssertNil(try aggregator.ingest(line: ""))
        XCTAssertNil(try aggregator.ingest(line: "not json"))
        XCTAssertNil(try aggregator.ingest(line: #"{"nothing":"useful"}"#))
    }

    func testErrorMessagesTellPeopleWhatToDo() {
        XCTAssertTrue(DownloadError.ollamaNotRunning.localizedDescription.contains("Open the Ollama app"))
        XCTAssertTrue(DownloadError.needsAuthentication.localizedDescription.contains("hf auth login"))
        XCTAssertTrue(DownloadError.notEnoughSpace(needed: 5_000_000_000, available: 1_000_000_000).localizedDescription.contains("5"))
    }
}

final class HuggingFaceClientTests: XCTestCase {
    func testDecodeSearchResultsToleratesMissingFields() throws {
        let json = #"""
        [
          {"_id":"1","id":"mlx-community/Llama-3.2-3B-Instruct-4bit","downloads":12345,"likes":42,"pipeline_tag":"text-generation","tags":["mlx","safetensors"]},
          {"modelId":"bartowski/Foo-GGUF"}
        ]
        """#
        let repos = try HuggingFaceClient.decodeSearch(Data(json.utf8))
        XCTAssertEqual(repos.map { $0.id }, ["mlx-community/Llama-3.2-3B-Instruct-4bit", "bartowski/Foo-GGUF"])
        XCTAssertEqual(repos[0].downloads, 12_345)
        XCTAssertEqual(repos[0].pipelineTag, "text-generation")
        XCTAssertEqual(repos[1].downloads, 0)
        XCTAssertTrue(repos[1].tags.isEmpty)
    }

    func testDecodeDetailsUsesLFSHashAndSize() throws {
        let json = #"""
        {
          "id": "org/model-GGUF",
          "sha": "deadbeef",
          "siblings": [
            {"rfilename": "model-Q4_K_M.gguf", "size": 133, "blobId": "gitid1", "lfs": {"sha256": "lfshash", "size": 2000000000, "pointerSize": 133}},
            {"rfilename": "model-Q8_0.gguf", "blobId": "gitid2", "lfs": {"sha256": "lfshash2", "size": 4000000000}},
            {"rfilename": "README.md", "size": 900, "blobId": "gitid3"}
          ]
        }
        """#
        let details = try HuggingFaceClient.decodeDetails(Data(json.utf8), fallbackID: "x/y")
        XCTAssertEqual(details.id, "org/model-GGUF")
        XCTAssertEqual(details.revision, "deadbeef")
        XCTAssertEqual(details.totalBytes, 6_000_000_900)
        XCTAssertEqual(details.ggufFiles.map { $0.path }, ["model-Q4_K_M.gguf", "model-Q8_0.gguf"], "smallest first")
        XCTAssertEqual(details.files[0].etag, "lfshash")
        XCTAssertEqual(details.files[2].etag, "gitid3")
    }

    func testDetailsWithoutACommitAreRejected() {
        XCTAssertThrowsError(try HuggingFaceClient.decodeDetails(Data(#"{"id":"a/b"}"#.utf8), fallbackID: "a/b"))
    }

    func testResolveURLAndAuthorizationOnlyForHuggingFaceHost() {
        let client = HuggingFaceClient(token: "secret")
        let url = client.resolveURL(repo: "org/name", revision: "abc", path: "sub/file.gguf")
        XCTAssertEqual(url.absoluteString, "https://huggingface.co/org/name/resolve/abc/sub/file.gguf")
        XCTAssertEqual(client.authorizedRequest(url).value(forHTTPHeaderField: "Authorization"), "Bearer secret")
        XCTAssertNil(client.authorizedRequest(URL(string: "https://cdn.example.com/x")!).value(forHTTPHeaderField: "Authorization"))
    }

    func testTokenLookupOrder() throws {
        let tmp = try TempDir()
        try tmp.file(".cache/huggingface/token", text: "  filetoken\n")
        XCTAssertEqual(HFToken.load(environment: ["HF_TOKEN": "envtoken"], home: tmp.url), "envtoken")
        XCTAssertEqual(HFToken.load(environment: [:], home: tmp.url), "filetoken")
        XCTAssertNil(HFToken.load(environment: [:], home: tmp.url.appendingPathComponent("empty")))
    }

    func testFileEtagFallsBackToAStablePathBasedName() {
        XCTAssertEqual(HFRepoFile(path: "a/b.txt", size: 1).etag, "pantry-a_b.txt")
    }
}

final class HFCacheLayoutTests: XCTestCase {
    func testRelativeLinkDepthMatchesFileDepth() {
        XCTAssertEqual(HFCacheLayout.relativeBlobTarget(forFilePath: "config.json", etag: "e"), "../../blobs/e")
        XCTAssertEqual(HFCacheLayout.relativeBlobTarget(forFilePath: "unet/model.safetensors", etag: "e"), "../../../blobs/e")
        XCTAssertEqual(HFCacheLayout.relativeBlobTarget(forFilePath: "a/b/c.bin", etag: "e"), "../../../../blobs/e")
    }

    func testCommitCreatesResolvableSymlinksAndRefs() throws {
        let tmp = try TempDir()
        let layout = HFCacheLayout(hubRoot: tmp.url)
        let repo = "org/name"
        try FileManager.default.createDirectory(at: layout.blobsDir(for: repo), withIntermediateDirectories: true)
        try Data("top".utf8).write(to: layout.blobURL(repo: repo, etag: "e1"))
        try Data("nested".utf8).write(to: layout.blobURL(repo: repo, etag: "e2"))

        try layout.commit(repo: repo, revision: "rev1", files: [("config.json", "e1"), ("sub/dir/weights.bin", "e2")])

        let snapshot = layout.snapshotURL(repo: repo, revision: "rev1")
        XCTAssertEqual(try String(contentsOf: snapshot.appendingPathComponent("config.json"), encoding: .utf8), "top")
        XCTAssertEqual(try String(contentsOf: snapshot.appendingPathComponent("sub/dir/weights.bin"), encoding: .utf8), "nested")
        XCTAssertEqual(try String(contentsOf: layout.repoDir(for: repo).appendingPathComponent("refs/main"), encoding: .utf8), "rev1")
        XCTAssertEqual(layout.repoDir(for: repo).lastPathComponent, "models--org--name")

        // Committing again replaces links instead of failing.
        XCTAssertNoThrow(try layout.commit(repo: repo, revision: "rev1", files: [("config.json", "e1")]))
    }

    func testWhatTheDownloaderWritesTheScannerReadsBack() throws {
        let tmp = try TempDir()
        let layout = HFCacheLayout(hubRoot: tmp.url)
        let repo = "mlx-community/Tiny-1B-Instruct-4bit"
        try FileManager.default.createDirectory(at: layout.blobsDir(for: repo), withIntermediateDirectories: true)
        try Data(repeating: 1, count: 300).write(to: layout.blobURL(repo: repo, etag: "w"))
        try Data(#"{"quantization":{"bits":4}}"#.utf8).write(to: layout.blobURL(repo: repo, etag: "c"))
        try layout.commit(repo: repo, revision: "r", files: [("model.safetensors", "w"), ("config.json", "c")])

        let entry = try XCTUnwrap(try HuggingFaceCacheScanner(hubRoot: tmp.url, minimumCandidateBytes: 1).scan().first)
        XCTAssertEqual(entry.name, repo)
        XCTAssertEqual(entry.service, .mlx)
        XCTAssertEqual(entry.format, .safetensors)
        XCTAssertEqual(entry.quantization, "4-bit")
    }
}
