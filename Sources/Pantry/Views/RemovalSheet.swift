import PantryCore
import SwiftUI

/// The confirmation step. It states exactly what will happen, offers the recoverable option
/// as the default, and keeps the irreversible one visually and physically apart.
struct RemovalSheet: View {
    @EnvironmentObject private var model: AppModel
    @State private var confirmingPermanent = false

    var body: some View {
        if let plan = model.pendingRemoval {
            content(plan)
        }
    }

    private func content(_ plan: RemovalPlan) -> some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack(alignment: .firstTextBaseline) {
                Text(title(plan)).font(.title2.weight(.semibold))
                Spacer()
            }

            ScrollView {
                VStack(spacing: 0) {
                    ForEach(plan.entries) { entry in
                        HStack(spacing: 10) {
                            ServiceBadge(service: entry.service)
                            Text(entry.name).lineLimit(1).truncationMode(.middle)
                            Spacer()
                            Text(ByteFormat.string(entry.sizeBytes)).monospacedDigit().foregroundStyle(.secondary)
                        }
                        .padding(.vertical, 8)
                        Divider()
                    }
                }
            }
            .frame(maxHeight: 190)

            VStack(alignment: .leading, spacing: 6) {
                Label("Frees \(ByteFormat.string(plan.reclaimableBytes))", systemImage: "internaldrive")
                    .font(.headline)
                if plan.keptBytes > 0 {
                    Text("\(ByteFormat.string(plan.keptBytes)) is shared with \(sharedWith(plan)) and will stay.")
                        .font(.callout).foregroundStyle(.secondary)
                }
                Text("Models can be downloaded again later. Moving to the Trash lets you undo this; the space is freed when you empty the Trash.")
                    .font(.callout).foregroundStyle(.secondary)
            }

            HStack {
                // Irreversible action: far left, plain, with its own confirmation.
                Button("Delete Permanently…", role: .destructive) { confirmingPermanent = true }
                Spacer()
                Button("Cancel") { model.cancelRemoval() }
                    .keyboardShortcut(.cancelAction)
                Button("Move to Trash") {
                    Task { await model.confirmRemoval(mode: .moveToTrash) }
                }
                .keyboardShortcut(.defaultAction)
                .buttonStyle(.borderedProminent)
            }
            .controlSize(.large)
        }
        .padding(24)
        .frame(width: 520)
        .confirmationDialog(
            "Delete permanently?",
            isPresented: $confirmingPermanent,
            titleVisibility: .visible
        ) {
            Button("Delete \(ByteFormat.string(plan.reclaimableBytes))", role: .destructive) {
                Task { await model.confirmRemoval(mode: .deletePermanently) }
            }
            Button("Keep", role: .cancel) {}
        } message: {
            Text("This can't be undone. The files skip the Trash.")
        }
    }

    private func title(_ plan: RemovalPlan) -> String {
        plan.entries.count == 1 ? "Remove “\(plan.entries[0].name)”?" : "Remove \(plan.entries.count) models?"
    }

    private func sharedWith(_ plan: RemovalPlan) -> String {
        let names = Set(plan.keptBlobs.flatMap { $0.stillUsedBy }).sorted()
        switch names.count {
        case 0: return "another model"
        case 1: return names[0]
        case 2: return "\(names[0]) and \(names[1])"
        default: return "\(names[0]) and \(names.count - 1) others"
        }
    }
}
