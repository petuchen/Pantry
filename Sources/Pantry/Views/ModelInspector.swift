import PantryCore
import SwiftUI

/// Everything about one model, with the technical detail tucked below the fold (progressive disclosure).
struct ModelInspector: View {
    @EnvironmentObject private var model: AppModel
    let entry: ModelEntry
    @State private var showTechnical = false

    private var plan: RemovalPlan {
        RemovalPlanner.plan(removing: [entry], from: model.entries)
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                VStack(alignment: .leading, spacing: 8) {
                    Text(entry.name)
                        .font(.title3.weight(.semibold))
                        .textSelection(.enabled)
                    ServiceBadge(service: entry.service)
                }

                if entry.isIncomplete {
                    Label("This looks like an interrupted download. It may not work, and it may be using space.", systemImage: "exclamationmark.triangle.fill")
                        .font(.callout)
                        .foregroundStyle(.orange)
                }

                Grid(alignment: .leading, horizontalSpacing: 12, verticalSpacing: 8) {
                    GridRow {
                        Text("Size").foregroundStyle(.secondary)
                        Text(ByteFormat.string(entry.sizeBytes)).monospacedDigit()
                    }
                    GridRow {
                        Text("Frees").foregroundStyle(.secondary)
                        VStack(alignment: .leading, spacing: 2) {
                            Text(ByteFormat.string(plan.reclaimableBytes)).monospacedDigit()
                            if plan.keptBytes > 0 {
                                Text("\(ByteFormat.string(plan.keptBytes)) is shared with another model and stays.")
                                    .font(.caption).foregroundStyle(.secondary)
                            }
                        }
                    }
                    GridRow {
                        Text("Used for").foregroundStyle(.secondary)
                        Menu {
                            ForEach(ModelCategory.allCases) { category in
                                Button {
                                    model.setCategory(category, for: [entry.id])
                                } label: {
                                    Label(category.displayName, systemImage: category.symbolName)
                                }
                            }
                        } label: {
                            CategoryLabel(category: entry.category, short: false)
                        }
                        .menuStyle(.borderlessButton)
                        .fixedSize()
                    }
                    if let modified = entry.modifiedAt {
                        GridRow {
                            Text("Modified").foregroundStyle(.secondary)
                            Text(modified, format: .dateTime.year().month(.abbreviated).day())
                        }
                    }
                }

                HStack {
                    Button("Reveal in Finder") { Finder.reveal(entry.revealURL) }
                    Spacer()
                    Button("Remove…", role: .destructive) { model.requestRemoval(of: [entry.id]) }
                }

                DisclosureGroup("Technical details", isExpanded: $showTechnical) {
                    VStack(alignment: .leading, spacing: 8) {
                        detail("Format", entry.format.displayName)
                        if let parameters = entry.parameterSize { detail("Parameters", parameters) }
                        if let quantization = entry.quantization { detail("Quantization", quantization) }
                        detail("Location", entry.revealURL.path, monospaced: true)
                        if !entry.blobs.isEmpty { detail("Layers", "\(entry.blobs.count) shared-capable blobs") }
                    }
                    .padding(.top, 8)
                }
            }
            .padding(16)
        }
    }

    private func detail(_ title: String, _ value: String, monospaced: Bool = false) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(title).font(.caption).foregroundStyle(.secondary)
            Text(value)
                .font(monospaced ? .caption.monospaced() : .callout)
                .textSelection(.enabled)
        }
    }
}
