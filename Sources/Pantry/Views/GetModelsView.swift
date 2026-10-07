import PantryCore
import SwiftUI

struct GetModelsView: View {
    @EnvironmentObject private var model: AppModel
    @State private var service: ModelService = .ollama

    var body: some View {
        VStack(spacing: 0) {
            Picker("Download from", selection: $service) {
                ForEach(ModelService.allCases.filter { $0 != .other }) { service in
                    Text(service.displayName).tag(service)
                }
            }
            .pickerStyle(.segmented)
            .labelsHidden()
            .padding(.horizontal, Spacing.page)
            .padding(.vertical, 14)

            Divider()

            Group {
                switch service {
                case .ollama:
                    OllamaPullPane()
                case .mlx, .huggingFace, .llamaCpp:
                    HuggingFacePane(service: service)
                        .id(service)
                case .other:
                    EmptyView()
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)

            if !model.downloads.isEmpty {
                Divider()
                DownloadsList()
            }
        }
        .navigationTitle("Get Models")
    }
}

// MARK: - Ollama

private struct OllamaPullPane: View {
    @EnvironmentObject private var model: AppModel
    @State private var input = ""

    private struct Suggestion: Identifiable {
        let name: String
        let category: ModelCategory
        var id: String { name }
    }

    /// Starting points grouped by purpose, so people can browse by what they need.
    private let suggestions: [Suggestion] = [
        Suggestion(name: "llama3.2:3b", category: .general),
        Suggestion(name: "qwen2.5-coder:7b", category: .coding),
        Suggestion(name: "deepseek-r1:7b", category: .reasoning),
        Suggestion(name: "llava:7b", category: .vision),
        Suggestion(name: "nomic-embed-text", category: .embedding),
        Suggestion(name: "llama-guard3:1b", category: .safety),
    ]

    private var parsed: String? { ModelReference.ollamaName(from: input) }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: Spacing.section) {
                VStack(alignment: .leading, spacing: 8) {
                    Text("Pull a model with Ollama").font(.title2.weight(.semibold))
                    Text("Type a model name, or paste a command or link. Pantry downloads it through the Ollama app running on this Mac.")
                        .foregroundStyle(.secondary)
                }

                VStack(alignment: .leading, spacing: 8) {
                    HStack {
                        TextField("llama3.2:3b", text: $input)
                            .textFieldStyle(.roundedBorder)
                            .controlSize(.large)
                            .onSubmit(pull)
                        Button("Pull", action: pull)
                            .buttonStyle(.borderedProminent)
                            .controlSize(.large)
                            .keyboardShortcut(.defaultAction)
                            .disabled(parsed == nil)
                    }
                    if !input.trimmingCharacters(in: .whitespaces).isEmpty && parsed == nil {
                        Text("That doesn't look like an Ollama model name. Try something like llama3.2:3b.")
                            .font(.callout).foregroundStyle(.secondary)
                    } else if let parsed, parsed != input.trimmingCharacters(in: .whitespacesAndNewlines) {
                        Text("Will pull \(parsed)").font(.callout).foregroundStyle(.secondary)
                    }
                }

                VStack(alignment: .leading, spacing: 10) {
                    Text("Popular starting points").font(.headline)
                    LazyVGrid(columns: [GridItem(.adaptive(minimum: 210), spacing: 10)], alignment: .leading, spacing: 10) {
                        ForEach(suggestions) { suggestion in
                            Button {
                                input = suggestion.name
                            } label: {
                                HStack {
                                    Image(systemName: suggestion.category.symbolName).frame(width: 20)
                                    VStack(alignment: .leading, spacing: 1) {
                                        Text(suggestion.name)
                                        Text(suggestion.category.shortName).font(.caption).foregroundStyle(.secondary)
                                    }
                                    Spacer()
                                }
                                .padding(.vertical, 6)
                                .padding(.horizontal, 10)
                                .frame(maxWidth: .infinity, minHeight: 44)
                                .contentShape(Rectangle())
                            }
                            .buttonStyle(.bordered)
                        }
                    }
                    Link("Browse all models on ollama.com", destination: URL(string: "https://ollama.com/library")!)
                        .font(.callout)
                }
            }
            .padding(Spacing.page)
            .frame(maxWidth: 760, alignment: .leading)
            .frame(maxWidth: .infinity)
        }
    }

    private func pull() {
        guard let name = parsed else { return }
        model.startOllamaPull(name: name)
        input = ""
    }
}

// MARK: - Hugging Face / MLX / llama.cpp

private struct HuggingFacePane: View {
    @EnvironmentObject private var model: AppModel
    let service: ModelService

    @State private var query = ""
    @State private var results: [HFRepoSummary] = []
    @State private var isSearching = false
    @State private var searchError: String?
    @State private var selectedID: String?
    @State private var details: HFRepoDetails?
    @State private var isLoadingDetails = false
    @State private var detailsError: String?

    private let client = HuggingFaceClient()

    private var filter: HFSearchFilter {
        switch service {
        case .mlx: return .mlx
        case .llamaCpp: return .gguf
        default: return .any
        }
    }

    private var directRepo: String? { ModelReference.huggingFaceRepo(from: query) }

    var body: some View {
        HSplitView {
            VStack(spacing: 0) {
                TextField(placeholder, text: $query)
                    .textFieldStyle(.roundedBorder)
                    .controlSize(.large)
                    .padding(12)
                resultsList
            }
            .frame(minWidth: 320, idealWidth: 380)

            detailPane
                .frame(minWidth: 380, maxWidth: .infinity, maxHeight: .infinity)
        }
        .task(id: query) { await search() }
        .task(id: selectedID) { await loadDetails() }
    }

    private var placeholder: String {
        switch service {
        case .mlx: return "Search MLX models, or paste a link"
        case .llamaCpp: return "Search GGUF models, or paste a link"
        default: return "Search Hugging Face, or paste a link"
        }
    }

    @ViewBuilder
    private var resultsList: some View {
        if let searchError {
            ContentUnavailableView("Couldn't reach Hugging Face", systemImage: "wifi.slash", description: Text(searchError))
        } else {
            List(selection: $selectedID) {
                if let direct = directRepo, !results.contains(where: { $0.id == direct }) {
                    Label(direct, systemImage: "link")
                        .tag(direct as String?)
                }
                Section(query.trimmingCharacters(in: .whitespaces).isEmpty ? "Most downloaded" : "Results") {
                    ForEach(results) { repo in
                        VStack(alignment: .leading, spacing: 3) {
                            Text(repo.id).lineLimit(1).truncationMode(.middle)
                            HStack(spacing: 10) {
                                Label(compactNumber(repo.downloads), systemImage: "arrow.down.circle")
                                Label(compactNumber(repo.likes), systemImage: "heart")
                                if let tag = repo.pipelineTag { Text(tag) }
                            }
                            .font(.caption)
                            .foregroundStyle(.secondary)
                        }
                        .padding(.vertical, 2)
                        .tag(repo.id as String?)
                    }
                }
            }
            .overlay {
                if isSearching && results.isEmpty { ProgressView() }
            }
        }
    }

    @ViewBuilder
    private var detailPane: some View {
        if selectedID == nil {
            ContentUnavailableView("Choose a model", systemImage: "arrow.left", description: Text("Pick one from the list to see what it contains and how big it is."))
        } else if isLoadingDetails {
            VStack(spacing: 10) {
                ProgressView()
                Text("Loading details…").foregroundStyle(.secondary)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        } else if let detailsError {
            ContentUnavailableView("Couldn't load this model", systemImage: "exclamationmark.triangle", description: Text(detailsError))
        } else if let details {
            RepoDetailView(service: service, details: details)
        }
    }

    // MARK: Loading

    private func search() async {
        // Debounce typing so it does not fire a request per keystroke, but show the initial
        // list immediately (Doherty threshold: no artificial wait on first paint).
        if !query.isEmpty {
            try? await Task.sleep(nanoseconds: 350_000_000)
            if Task.isCancelled { return }
        }
        isSearching = true
        defer { isSearching = false }
        do {
            results = try await client.search(query: directRepo == nil ? query : "", filter: filter)
            searchError = nil
        } catch {
            if Task.isCancelled { return }
            searchError = error.localizedDescription
        }
    }

    private func loadDetails() async {
        details = nil
        detailsError = nil
        guard let id = selectedID else { return }
        isLoadingDetails = true
        defer { isLoadingDetails = false }
        do {
            let loaded = try await client.details(repo: id)
            if Task.isCancelled { return }
            details = loaded
        } catch {
            if Task.isCancelled { return }
            detailsError = error.localizedDescription
        }
    }
}

private struct RepoDetailView: View {
    @EnvironmentObject private var model: AppModel
    let service: ModelService
    let details: HFRepoDetails

    private var destination: URL { model.locations.downloadFolder(for: service) }
    private var free: Int64? { DiskSpace.availableBytes(at: FileManager.default.homeDirectoryForCurrentUser) }
    private var alreadyHave: Bool { model.entries.contains { $0.name == details.id } }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                Text(details.id).font(.title2.weight(.semibold)).textSelection(.enabled)

                if alreadyHave {
                    Label("Already on this Mac", systemImage: "checkmark.circle.fill").foregroundStyle(.green)
                }

                if service == .llamaCpp {
                    ggufList
                } else {
                    wholeRepo
                }

                Text("Saves to \(destination.path)")
                    .font(.caption).foregroundStyle(.secondary).textSelection(.enabled)
            }
            .padding(Spacing.page)
        }
    }

    private var wholeRepo: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("\(details.files.count) files · \(ByteFormat.string(details.totalBytes))").foregroundStyle(.secondary)
            if let free, details.totalBytes > free {
                Label("Not enough free space (\(ByteFormat.string(free)) available).", systemImage: "exclamationmark.triangle.fill")
                    .foregroundStyle(.orange)
            }
            Button {
                model.startRepoDownload(details, service: service)
            } label: {
                Label("Download \(ByteFormat.string(details.totalBytes))", systemImage: "arrow.down.circle.fill")
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.large)
            .disabled(free.map { details.totalBytes > $0 } ?? false)
            if details.ggufFiles.count > 1 {
                Text("This repository holds several quantizations. For llama.cpp, choose a single file in the llama.cpp tab instead.")
                    .font(.callout).foregroundStyle(.secondary)
            }
        }
    }

    @ViewBuilder
    private var ggufList: some View {
        if details.ggufFiles.isEmpty {
            Text("This repository has no .gguf files.").foregroundStyle(.secondary)
        } else {
            Text("Choose one file. Smaller files use less memory and are a little less accurate.")
                .font(.callout).foregroundStyle(.secondary)
            VStack(spacing: 0) {
                ForEach(details.ggufFiles, id: \.path) { file in
                    HStack {
                        VStack(alignment: .leading, spacing: 2) {
                            Text(file.path).lineLimit(1).truncationMode(.middle)
                            if let quant = ModelNameParser.parse(file.path).quantization {
                                Text(quant).font(.caption).foregroundStyle(.secondary)
                            }
                        }
                        Spacer()
                        Text(ByteFormat.string(file.size)).monospacedDigit().foregroundStyle(.secondary)
                        Button("Download") {
                            model.startGGUFDownload(repo: details.id, revision: details.revision, file: file)
                        }
                        .disabled(free.map { file.size > $0 } ?? false)
                    }
                    .padding(.vertical, 8)
                    Divider()
                }
            }
        }
    }
}

// MARK: - Downloads

private struct DownloadsList: View {
    @EnvironmentObject private var model: AppModel

    var body: some View {
        ScrollView {
            VStack(spacing: 0) {
                ForEach(model.downloads) { job in
                    DownloadRow(job: job)
                    Divider()
                }
            }
        }
        .frame(maxHeight: 190)
        .background(.bar)
    }
}

private struct DownloadRow: View {
    @EnvironmentObject private var model: AppModel
    @ObservedObject var job: DownloadJob

    var body: some View {
        HStack(spacing: 12) {
            ServiceBadge(service: job.service)
            VStack(alignment: .leading, spacing: 3) {
                Text(job.title).lineLimit(1).truncationMode(.middle)
                status
            }
            Spacer()
            trailing
        }
        .padding(.horizontal, Spacing.page)
        .padding(.vertical, 10)
    }

    @ViewBuilder
    private var status: some View {
        switch job.state {
        case .running:
            VStack(alignment: .leading, spacing: 3) {
                if let fraction = job.progress.fraction {
                    ProgressView(value: fraction)
                } else {
                    ProgressView().progressViewStyle(.linear)
                }
                Text(progressText).font(.caption).foregroundStyle(.secondary)
            }
            .frame(maxWidth: 360, alignment: .leading)
        case .finished:
            Label("Ready to use", systemImage: "checkmark.circle.fill").font(.caption).foregroundStyle(.green)
        case .failed(let message):
            Label(message, systemImage: "exclamationmark.triangle.fill").font(.caption).foregroundStyle(.orange)
        case .cancelled:
            Text("Cancelled").font(.caption).foregroundStyle(.secondary)
        }
    }

    @ViewBuilder
    private var trailing: some View {
        switch job.state {
        case .running:
            Button("Cancel") { job.cancel() }
        case .finished:
            Button("Show in Models") { model.sidebarSelection = .library }
            Button("Dismiss") { model.dismiss(job) }.buttonStyle(.borderless)
        case .failed, .cancelled:
            Button("Dismiss") { model.dismiss(job) }
        }
    }

    private var progressText: String {
        let p = job.progress
        guard let total = p.totalBytes, total > 0 else { return p.phase }
        return "\(p.phase) · \(ByteFormat.string(p.completedBytes)) of \(ByteFormat.string(total))"
    }
}
