import PantryCore
import SwiftUI

struct CleanupView: View {
    @EnvironmentObject private var model: AppModel

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: Spacing.section) {
                header

                if model.isCheckingDuplicates && model.cleanupCount == 0 {
                    HStack(spacing: 10) {
                        ProgressView().controlSize(.small)
                        Text("Comparing files that have the same size…").foregroundStyle(.secondary)
                    }
                } else if model.cleanupCount == 0 {
                    ContentUnavailableView(
                        "Nothing to clean up",
                        systemImage: "checkmark.seal",
                        description: Text("No identical files and no copies of the same model were found across your folders.")
                    )
                } else {
                    if !model.identicalGroups.isEmpty {
                        section(
                            title: "Identical copies",
                            explanation: "These files are byte-for-byte the same. Keeping one is enough.",
                            groups: model.identicalGroups
                        )
                    }
                    if !model.similarGroups.isEmpty {
                        section(
                            title: "Same model, different builds",
                            explanation: "These look like the same model in different formats or quantizations. They are not identical, so only you can say which to keep.",
                            groups: model.similarGroups
                        )
                    }
                }
            }
            .padding(Spacing.page)
            .frame(maxWidth: 860, alignment: .leading)
            .frame(maxWidth: .infinity)
        }
        .navigationTitle("Cleanup")
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(model.reclaimableBytes > 0 ? "Up to \(ByteFormat.string(model.reclaimableBytes)) can be freed" : "Duplicates and lookalikes")
                .font(.system(size: 32, weight: .semibold, design: .rounded))
            Text("Pantry never removes anything on its own. Pick a copy and you will be asked to confirm.")
                .foregroundStyle(.secondary)
        }
    }

    private func section(title: String, explanation: String, groups: [DuplicateGroup]) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            VStack(alignment: .leading, spacing: 2) {
                Text(title).font(.title3.weight(.semibold))
                Text(explanation).font(.callout).foregroundStyle(.secondary)
            }
            ForEach(groups) { group in
                GroupCard(group: group)
            }
        }
    }
}

private struct GroupCard: View {
    @EnvironmentObject private var model: AppModel
    let group: DuplicateGroup

    var body: some View {
        Card {
            HStack {
                Text(summary).font(.headline)
                Spacer()
                if let reclaim = group.reclaimableBytes {
                    Text("Frees \(ByteFormat.string(reclaim)) by keeping one")
                        .font(.callout).foregroundStyle(.secondary)
                }
            }
            VStack(spacing: 0) {
                ForEach(Array(group.entries.enumerated()), id: \.element.id) { index, entry in
                    if index > 0 { Divider() }
                    row(entry)
                }
            }
        }
    }

    private var summary: String {
        group.kind == .identical
            ? "\(group.entries.count) copies of the same file"
            : "\(group.entries.count) builds of the same model"
    }

    private func row(_ entry: ModelEntry) -> some View {
        let reclaim = RemovalPlanner.plan(removing: [entry], from: model.entries).reclaimableBytes
        return HStack(alignment: .center, spacing: 12) {
            VStack(alignment: .leading, spacing: 4) {
                HStack(spacing: 8) {
                    ServiceBadge(service: entry.service)
                    Text(entry.name).lineLimit(1).truncationMode(.middle)
                }
                HStack(spacing: 8) {
                    Text(entry.technicalSummary)
                    Text("·")
                    Text(entry.revealURL.deletingLastPathComponent().path)
                        .lineLimit(1).truncationMode(.head)
                }
                .font(.caption)
                .foregroundStyle(.secondary)
            }
            Spacer(minLength: 12)
            VStack(alignment: .trailing, spacing: 2) {
                Text(ByteFormat.string(entry.sizeBytes)).monospacedDigit()
                Text("frees \(ByteFormat.string(reclaim))").font(.caption).foregroundStyle(.secondary)
            }
            Button("Reveal") { Finder.reveal(entry.revealURL) }
                .buttonStyle(.borderless)
            Button("Remove…", role: .destructive) { model.requestRemoval(of: [entry.id]) }
        }
        .padding(.vertical, 10)
    }
}
