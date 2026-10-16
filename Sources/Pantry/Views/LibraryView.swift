import PantryCore
import SwiftUI

struct LibraryView: View {
    @EnvironmentObject private var model: AppModel
    @State private var sortOrder = [KeyPathComparator(\ModelEntry.sizeBytes, order: .reverse)]
    @State private var showInspector = false

    private var filtered: [ModelEntry] {
        let query = model.librarySearch.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        return model.entries
            .filter { model.libraryServiceFilter == nil || $0.service == model.libraryServiceFilter }
            .filter { model.libraryCategoryFilter == nil || $0.category == model.libraryCategoryFilter }
            .filter { query.isEmpty || $0.name.lowercased().contains(query) }
            .sorted(using: sortOrder)
    }

    private var selectedEntries: [ModelEntry] {
        model.entries.filter { model.librarySelection.contains($0.id) }
    }

    var body: some View {
        let rows = filtered
        VStack(spacing: 0) {
            if model.entries.isEmpty {
                EmptyLibrary()
            } else if rows.isEmpty {
                ContentUnavailableView {
                    Label("No matching models", systemImage: "line.3.horizontal.decrease.circle")
                } description: {
                    Text("Nothing fits the current filters.")
                } actions: {
                    Button("Clear Filters") {
                        model.libraryServiceFilter = nil
                        model.libraryCategoryFilter = nil
                        model.librarySearch = ""
                    }
                }
            } else {
                table(rows)
                StatusBar(selected: selectedEntries, visibleCount: rows.count)
            }
        }
        .navigationTitle("Models")
        .searchable(text: $model.librarySearch, placement: .toolbar, prompt: "Search models")
        .toolbar { toolbar }
        .inspector(isPresented: $showInspector) {
            Group {
                if selectedEntries.count == 1, let entry = selectedEntries.first {
                    ModelInspector(entry: entry)
                } else {
                    ContentUnavailableView("Select a model", systemImage: "sidebar.right", description: Text("Details appear here."))
                }
            }
            .inspectorColumnWidth(min: 260, ideal: 300, max: 380)
        }
    }

    private func table(_ rows: [ModelEntry]) -> some View {
        Table(rows, selection: $model.librarySelection, sortOrder: $sortOrder) {
            TableColumn("Name", value: \.name) { entry in
                VStack(alignment: .leading, spacing: 2) {
                    HStack(spacing: 6) {
                        Text(entry.name).lineLimit(1).truncationMode(.middle)
                        if entry.isIncomplete {
                            Label("Incomplete", systemImage: "exclamationmark.triangle.fill")
                                .labelStyle(.titleAndIcon)
                                .font(.caption2)
                                .foregroundStyle(.orange)
                        }
                    }
                    Text(entry.technicalSummary).font(.caption).foregroundStyle(.secondary)
                }
            }
            .width(min: 220, ideal: 320)

            TableColumn("Service", value: \.service.displayName) { entry in
                ServiceBadge(service: entry.service)
            }
            .width(min: 120, ideal: 130, max: 150)

            TableColumn("Used for", value: \.category.displayName) { entry in
                CategoryLabel(category: entry.category)
            }
            .width(min: 110, ideal: 130)

            TableColumn("Size", value: \.sizeBytes) { entry in
                Text(ByteFormat.string(entry.sizeBytes)).monospacedDigit()
            }
            .width(min: 70, ideal: 80, max: 100)

            TableColumn("Modified", value: \.modifiedSortKey) { entry in
                if let date = entry.modifiedAt {
                    Text(date, format: .dateTime.year().month(.abbreviated).day()).foregroundStyle(.secondary)
                } else {
                    Text("—").foregroundStyle(.secondary)
                }
            }
            .width(min: 90, ideal: 100, max: 120)
        }
        .contextMenu(forSelectionType: ModelEntry.ID.self) { ids in
            contextMenu(for: ids)
        } primaryAction: { _ in
            showInspector = true
        }
        .onDeleteCommand {
            model.requestRemoval(of: model.librarySelection)
        }
    }

    @ViewBuilder
    private func contextMenu(for ids: Set<String>) -> some View {
        if ids.count == 1, let entry = model.entries.first(where: { ids.contains($0.id) }) {
            Button("Reveal in Finder") { Finder.reveal(entry.revealURL) }
            Button("Copy Name") { Finder.copy(entry.name) }
            Divider()
        }
        Menu("Change “Used for”") {
            ForEach(ModelCategory.allCases) { category in
                Button {
                    model.setCategory(category, for: ids)
                } label: {
                    Label(category.displayName, systemImage: category.symbolName)
                }
            }
        }
        Divider()
        Button("Remove…", role: .destructive) { model.requestRemoval(of: ids) }
    }

    @ToolbarContentBuilder
    private var toolbar: some ToolbarContent {
        ToolbarItemGroup(placement: .primaryAction) {
            Picker("Service", selection: $model.libraryServiceFilter) {
                Text("All services").tag(ModelService?.none)
                Divider()
                ForEach(ModelService.allCases) { service in
                    Label(service.displayName, systemImage: service.symbolName).tag(ModelService?.some(service))
                }
            }
            .pickerStyle(.menu)
            .help("Filter by service")

            Picker("Used for", selection: $model.libraryCategoryFilter) {
                Text("Any use").tag(ModelCategory?.none)
                Divider()
                ForEach(ModelCategory.allCases) { category in
                    Label(category.displayName, systemImage: category.symbolName).tag(ModelCategory?.some(category))
                }
            }
            .pickerStyle(.menu)
            .help("Filter by what the model is used for")

            Button {
                showInspector.toggle()
            } label: {
                Label("Details", systemImage: "sidebar.right")
            }
            .help("Show or hide details")
        }
    }
}

private struct StatusBar: View {
    @EnvironmentObject private var model: AppModel
    let selected: [ModelEntry]
    let visibleCount: Int

    var body: some View {
        HStack {
            if selected.isEmpty {
                Text(visibleCount == 1 ? "1 model" : "\(visibleCount) models")
                    .foregroundStyle(.secondary)
            } else {
                let plan = RemovalPlanner.plan(removing: selected, from: model.entries)
                Text("\(selected.count) selected · frees \(ByteFormat.string(plan.reclaimableBytes)) if removed")
                    .foregroundStyle(.secondary)
            }
            Spacer()
            // Deliberately the least prominent button in the window, and far from everything else.
            Button("Remove…", role: .destructive) {
                model.requestRemoval(of: Set(selected.map { $0.id }))
            }
            .disabled(selected.isEmpty)
            .help("Remove the selected models. You will be asked to confirm.")
        }
        .font(.callout)
        .padding(.horizontal, 16)
        .padding(.vertical, 8)
        .background(.bar)
    }
}

private struct EmptyLibrary: View {
    @EnvironmentObject private var model: AppModel

    var body: some View {
        ContentUnavailableView {
            Label("No models yet", systemImage: "tray")
        } description: {
            Text("Models you download with Ollama, MLX, llama.cpp or Hugging Face will show up here.")
        } actions: {
            Button("Get a Model") { model.sidebarSelection = .getModels }
                .buttonStyle(.borderedProminent)
        }
    }
}
