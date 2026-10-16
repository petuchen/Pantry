import PantryCore
import SwiftUI

struct OverviewView: View {
    @EnvironmentObject private var model: AppModel

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: Spacing.section) {
                if model.scanState != .finished && model.entries.isEmpty {
                    ScanningPlaceholder()
                } else if model.entries.isEmpty {
                    FirstRunEmptyState()
                } else {
                    Hero()
                    ServiceUsageCard()
                    HStack(alignment: .top, spacing: Spacing.section) {
                        CategoryUsageCard()
                        LargestModelsCard()
                    }
                    CleanupCallout()
                    if model.summary.incompleteCount > 0 { IncompleteNote() }
                }
                if !model.warnings.isEmpty { WarningsCard() }
            }
            .padding(Spacing.page)
            .frame(maxWidth: 940, alignment: .leading)
            .frame(maxWidth: .infinity)
        }
        .navigationTitle("Overview")
    }
}

// MARK: - Sections

private struct Hero: View {
    @EnvironmentObject private var model: AppModel

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(ByteFormat.string(model.summary.totalBytes))
                .font(.system(size: 52, weight: .semibold, design: .rounded))
                .monospacedDigit()
            Text(subtitle)
                .font(.title3)
                .foregroundStyle(.secondary)
        }
        .accessibilityElement(children: .combine)
    }

    private var subtitle: String {
        let models = model.summary.modelCount == 1 ? "1 model" : "\(model.summary.modelCount) models"
        let services = model.summary.byService.count == 1 ? "1 service" : "\(model.summary.byService.count) services"
        var text = "\(models) across \(services)"
        if let free = model.diskAvailable { text += " · \(ByteFormat.string(free)) free on this Mac" }
        return text
    }
}

private struct ServiceUsageCard: View {
    @EnvironmentObject private var model: AppModel

    var body: some View {
        Card(title: "Storage by service") {
            StackedUsageBar(segments: model.summary.byService.map {
                UsageSegment(id: $0.id, label: $0.service.displayName, color: $0.service.tint, value: Double($0.bytes))
            })
            VStack(spacing: 2) {
                ForEach(model.summary.byService) { usage in
                    Button {
                        model.showInLibrary(service: usage.service)
                    } label: {
                        HStack(spacing: 10) {
                            Image(systemName: "circle.fill").foregroundStyle(usage.service.tint).font(.caption2)
                            Label(usage.service.displayName, systemImage: usage.service.symbolName)
                            Spacer()
                            Text(usage.modelCount == 1 ? "1 model" : "\(usage.modelCount) models")
                                .foregroundStyle(.secondary)
                            Text(percent(usage.bytes))
                                .foregroundStyle(.secondary)
                                .frame(width: 44, alignment: .trailing)
                            Text(ByteFormat.string(usage.bytes))
                                .monospacedDigit()
                                .frame(width: 80, alignment: .trailing)
                        }
                        .padding(.vertical, 6)
                        .padding(.horizontal, 6)
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .help("Show \(usage.service.displayName) models")
                }
            }
            if model.summary.byService.contains(where: { $0.service == .ollama }) {
                Text("Layers that several Ollama models share are counted once.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
    }

    private func percent(_ bytes: Int64) -> String {
        guard model.summary.totalBytes > 0 else { return "0%" }
        return "\(Int((Double(bytes) / Double(model.summary.totalBytes) * 100).rounded()))%"
    }
}

private struct CategoryUsageCard: View {
    @EnvironmentObject private var model: AppModel

    var body: some View {
        Card(title: "What your models are for") {
            VStack(spacing: 2) {
                ForEach(model.summary.byCategory) { usage in
                    Button {
                        model.showInLibrary(category: usage.category)
                    } label: {
                        HStack {
                            CategoryLabel(category: usage.category, short: false)
                            Spacer()
                            Text("\(usage.modelCount)").foregroundStyle(.secondary)
                            Text(ByteFormat.string(usage.bytes))
                                .monospacedDigit()
                                .frame(width: 80, alignment: .trailing)
                        }
                        .padding(.vertical, 5)
                        .padding(.horizontal, 6)
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                }
            }
        }
    }
}

private struct LargestModelsCard: View {
    @EnvironmentObject private var model: AppModel

    var body: some View {
        Card(title: "Largest models") {
            VStack(spacing: 2) {
                ForEach(model.summary.largest) { entry in
                    Button {
                        model.showInLibrary(selecting: [entry.id])
                    } label: {
                        HStack {
                            VStack(alignment: .leading, spacing: 2) {
                                Text(entry.name).lineLimit(1).truncationMode(.middle)
                                Text(entry.service.displayName).font(.caption).foregroundStyle(.secondary)
                            }
                            Spacer()
                            Text(ByteFormat.string(entry.sizeBytes)).monospacedDigit()
                        }
                        .padding(.vertical, 5)
                        .padding(.horizontal, 6)
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                }
            }
        }
    }
}

/// The one element on this screen that gets accent treatment, and only when there is something to act on.
private struct CleanupCallout: View {
    @EnvironmentObject private var model: AppModel

    var body: some View {
        if model.isCheckingDuplicates && model.cleanupCount == 0 {
            HStack(spacing: 10) {
                ProgressView().controlSize(.small)
                Text("Checking for duplicates…").foregroundStyle(.secondary)
            }
            .padding(Spacing.card)
        } else if model.cleanupCount > 0 {
            HStack(alignment: .center, spacing: 16) {
                Image(systemName: "sparkles").font(.title).foregroundStyle(Color.accentColor)
                VStack(alignment: .leading, spacing: 4) {
                    Text(headline).font(.headline)
                    Text("Review copies of the same model and decide what to keep. Nothing is removed without your confirmation.")
                        .font(.callout).foregroundStyle(.secondary)
                }
                Spacer()
                Button("Review") { model.sidebarSelection = .cleanup }
                    .buttonStyle(.borderedProminent)
                    .controlSize(.large)
            }
            .padding(Spacing.card)
            .background(Color.accentColor.opacity(0.10), in: RoundedRectangle(cornerRadius: 12))
            .overlay(RoundedRectangle(cornerRadius: 12).strokeBorder(Color.accentColor.opacity(0.35)))
        } else {
            Label("No duplicate models found", systemImage: "checkmark.circle")
                .foregroundStyle(.secondary)
                .padding(Spacing.card)
        }
    }

    private var headline: String {
        if model.reclaimableBytes > 0 {
            return "Up to \(ByteFormat.string(model.reclaimableBytes)) can be freed"
        }
        let n = model.cleanupCount
        return n == 1 ? "1 group of similar models" : "\(n) groups of similar models"
    }
}

private struct IncompleteNote: View {
    @EnvironmentObject private var model: AppModel

    var body: some View {
        Label(
            model.summary.incompleteCount == 1
                ? "1 model looks like an interrupted download. It may be using space without working."
                : "\(model.summary.incompleteCount) models look like interrupted downloads. They may be using space without working.",
            systemImage: "exclamationmark.triangle"
        )
        .font(.callout)
        .foregroundStyle(.secondary)
    }
}

private struct WarningsCard: View {
    @EnvironmentObject private var model: AppModel

    var body: some View {
        Card(title: "Some folders couldn't be read") {
            ForEach(Array(model.warnings.enumerated()), id: \.offset) { _, warning in
                VStack(alignment: .leading, spacing: 2) {
                    Text(warning.source).font(.callout.weight(.medium))
                    Text(warning.message).font(.caption).foregroundStyle(.secondary)
                }
            }
            Text("If a folder is on an external drive, make sure it is connected. Pantry can also be given access in System Settings → Privacy & Security → Files and Folders.")
                .font(.caption).foregroundStyle(.secondary)
        }
    }
}

// MARK: - Empty states

private struct ScanningPlaceholder: View {
    var body: some View {
        VStack(alignment: .leading, spacing: Spacing.section) {
            // Skeleton of the finished layout, so the page does not jump when results arrive.
            RoundedRectangle(cornerRadius: 8).fill(Color.primary.opacity(0.07)).frame(width: 220, height: 52)
            RoundedRectangle(cornerRadius: 12).fill(Color.primary.opacity(0.05)).frame(height: 150)
            HStack(spacing: Spacing.section) {
                RoundedRectangle(cornerRadius: 12).fill(Color.primary.opacity(0.05)).frame(height: 180)
                RoundedRectangle(cornerRadius: 12).fill(Color.primary.opacity(0.05)).frame(height: 180)
            }
            HStack(spacing: 8) {
                ProgressView().controlSize(.small)
                Text("Looking through your model folders…").foregroundStyle(.secondary)
            }
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel("Scanning for models")
    }
}

private struct FirstRunEmptyState: View {
    @EnvironmentObject private var model: AppModel

    var body: some View {
        VStack(alignment: .leading, spacing: 20) {
            ContentUnavailableView {
                Label("No models found yet", systemImage: "tray")
            } description: {
                Text("Pantry looked in the places below. Get a model, or point Pantry at a folder where you keep them.")
            } actions: {
                Button("Get a Model") { model.sidebarSelection = .getModels }
                    .buttonStyle(.borderedProminent)
                    .controlSize(.large)
                SettingsLink { Text("Add a Folder…") }
                    .controlSize(.large)
            }
            Card(title: "Where Pantry looks") {
                ForEach(model.scannedFolders) { folder in
                    HStack(spacing: 8) {
                        Image(systemName: folder.exists ? "checkmark.circle.fill" : "minus.circle")
                            .foregroundStyle(folder.exists ? Color.green : Color.secondary)
                        Text(folder.service.displayName).frame(width: 100, alignment: .leading)
                        Text(folder.url.path).font(.callout.monospaced()).foregroundStyle(.secondary).lineLimit(1).truncationMode(.middle)
                        Spacer()
                        Text(folder.exists ? "Found" : "Not found").font(.caption).foregroundStyle(.secondary)
                    }
                }
            }
        }
    }
}
