import PantryCore
import SwiftUI

struct RootView: View {
    @EnvironmentObject private var model: AppModel

    var body: some View {
        NavigationSplitView {
            Sidebar()
                .navigationSplitViewColumnWidth(min: 190, ideal: 210, max: 260)
        } detail: {
            ZStack(alignment: .top) {
                detail
                if let report = model.removalReport {
                    RemovalReportBanner(report: report)
                        .padding(.top, 12)
                        .transition(.move(edge: .top).combined(with: .opacity))
                }
            }
            .animation(.easeOut(duration: 0.2), value: model.removalReport?.id)
        }
        .toolbar {
            ToolbarItem(placement: .navigation) {
                if model.scanState == .scanning {
                    ProgressView().controlSize(.small).help("Scanning model folders…")
                }
            }
        }
        .sheet(isPresented: Binding(
            get: { model.pendingRemoval != nil },
            set: { if !$0 { model.cancelRemoval() } }
        )) {
            RemovalSheet()
                .environmentObject(model)
        }
    }

    @ViewBuilder
    private var detail: some View {
        switch model.sidebarSelection ?? .overview {
        case .overview: OverviewView()
        case .library: LibraryView()
        case .cleanup: CleanupView()
        case .getModels: GetModelsView()
        }
    }
}

private struct Sidebar: View {
    @EnvironmentObject private var model: AppModel

    var body: some View {
        List(selection: $model.sidebarSelection) {
            ForEach(SidebarItem.allCases) { item in
                Label(item.title, systemImage: item.symbolName)
                    .badge(badge(for: item))
                    .tag(item)
            }
        }
        .listStyle(.sidebar)
        .safeAreaInset(edge: .bottom) {
            Button {
                Task { await model.refresh() }
            } label: {
                Label("Rescan", systemImage: "arrow.clockwise")
                    .frame(maxWidth: .infinity)
            }
            .controlSize(.large)
            .disabled(model.scanState == .scanning)
            .padding(12)
            .help("Look for models again (⌘R)")
        }
    }

    private func badge(for item: SidebarItem) -> Int {
        switch item {
        case .cleanup: return model.cleanupCount
        case .getModels: return model.runningDownloadCount
        default: return 0
        }
    }
}

/// Closes the loop after a removal: what was removed, how much space it freed, and what to do next.
private struct RemovalReportBanner: View {
    @EnvironmentObject private var model: AppModel
    let report: RemovalReport

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: report.result.isCompleteSuccess ? "checkmark.circle.fill" : "exclamationmark.triangle.fill")
                .font(.title2)
                .foregroundStyle(report.result.isCompleteSuccess ? Color.green : Color.orange)
            VStack(alignment: .leading, spacing: 4) {
                Text(headline).font(.headline)
                Text(detail).font(.callout).foregroundStyle(.secondary)
            }
            Spacer(minLength: 12)
            if report.result.mode == .moveToTrash && report.result.isCompleteSuccess {
                Button("Open Trash") { Finder.openTrash() }
            }
            Button {
                model.removalReport = nil
            } label: {
                Image(systemName: "xmark")
                    .frame(width: 28, height: 28)
            }
            .buttonStyle(.borderless)
            .help("Dismiss")
        }
        .padding(14)
        .frame(maxWidth: 560)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 12))
        .overlay(RoundedRectangle(cornerRadius: 12).strokeBorder(Color.primary.opacity(0.1)))
        .shadow(radius: 8, y: 2)
        .task(id: report.id) {
            // Failures stay until dismissed; successes get out of the way.
            guard report.result.isCompleteSuccess else { return }
            try? await Task.sleep(nanoseconds: 9_000_000_000)
            if model.removalReport?.id == report.id { model.removalReport = nil }
        }
    }

    private var headline: String {
        if !report.result.isCompleteSuccess { return "Some items couldn't be removed" }
        let count = report.modelNames.count
        let noun = count == 1 ? report.modelNames.first ?? "1 model" : "\(count) models"
        return report.result.mode == .moveToTrash ? "Moved \(noun) to the Trash" : "Removed \(noun)"
    }

    private var detail: String {
        let size = ByteFormat.string(report.result.bytesRemoved)
        if !report.result.isCompleteSuccess {
            return report.result.failures.first?.message ?? "Nothing was changed."
        }
        switch report.result.mode {
        case .moveToTrash: return "\(size) will be freed when you empty the Trash. You can put the items back until then."
        case .deletePermanently: return "\(size) freed."
        }
    }
}
