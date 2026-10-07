import AppKit
import PantryCore
import SwiftUI

/// The popover: the few numbers you would otherwise open the window for, and a way in.
/// Order is the order of questions people ask: how much? where? anything running? anything to do?
struct MenuBarContent: View {
    @EnvironmentObject private var model: AppModel
    @Environment(\.openWindow) private var openWindow

    private var running: [DownloadJob] { model.downloads.filter { $0.isRunning } }
    private var failedCount: Int {
        model.downloads.filter { if case .failed = $0.state { return true } else { return false } }.count
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            header

            if model.lastScan == nil {
                HStack(spacing: 8) {
                    ProgressView().controlSize(.small)
                    Text("Looking through your model folders…").foregroundStyle(.secondary)
                }
                .padding(.vertical, 12)
            } else if model.entries.isEmpty {
                emptyState
            } else {
                hero
                services
            }

            if !running.isEmpty || failedCount > 0 {
                downloads
            }

            if model.cleanupCount > 0 {
                cleanupButton
            }

            Divider()
            footer
        }
        .padding(16)
        .frame(width: 330)
        .task { await model.refreshIfStale() }
    }

    // MARK: Pieces

    private var header: some View {
        HStack {
            Text("Pantry").font(.headline)
            Spacer()
            if model.scanState == .scanning {
                ProgressView().controlSize(.small)
            } else {
                Button {
                    Task { await model.refresh() }
                } label: {
                    Image(systemName: "arrow.clockwise").frame(width: 28, height: 28)
                }
                .buttonStyle(.borderless)
                .help("Rescan models")
                .accessibilityLabel("Rescan models")
            }
        }
    }

    private var hero: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(ByteFormat.string(model.summary.totalBytes))
                .font(.system(size: 32, weight: .semibold, design: .rounded))
                .monospacedDigit()
            Text(subtitle).font(.callout).foregroundStyle(.secondary)
        }
        .accessibilityElement(children: .combine)
    }

    private var subtitle: String {
        let count = model.summary.modelCount
        var text = count == 1 ? "1 model" : "\(count) models"
        if let free = model.diskAvailable { text += " · \(ByteFormat.string(free)) free" }
        return text
    }

    private var services: some View {
        VStack(alignment: .leading, spacing: 8) {
            StackedUsageBar(segments: model.summary.byService.map {
                UsageSegment(id: $0.id, label: $0.service.displayName, color: $0.service.tint, value: Double($0.bytes))
            })
            VStack(spacing: 0) {
                ForEach(model.summary.byService) { usage in
                    Button {
                        show(.library, service: usage.service)
                    } label: {
                        HStack(spacing: 8) {
                            Image(systemName: "circle.fill").font(.system(size: 7)).foregroundStyle(usage.service.tint)
                            Text(usage.service.displayName)
                            Spacer()
                            Text(ByteFormat.string(usage.bytes)).monospacedDigit().foregroundStyle(.secondary)
                        }
                        .padding(.vertical, 5)
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .help("Show \(usage.service.displayName) models")
                }
            }
        }
    }

    private var emptyState: some View {
        VStack(alignment: .leading, spacing: 6) {
            Label("No models found yet", systemImage: "tray").font(.headline)
            Text("Get a model, or add the folder where you keep them.")
                .font(.callout).foregroundStyle(.secondary)
            Button("Get a Model") { show(.getModels) }
        }
        .padding(.vertical, 6)
    }

    private var downloads: some View {
        VStack(alignment: .leading, spacing: 10) {
            ForEach(running) { job in
                MenuBarDownloadRow(job: job)
            }
            if failedCount > 0 {
                Button {
                    show(.getModels)
                } label: {
                    Label(failedCount == 1 ? "1 download failed" : "\(failedCount) downloads failed", systemImage: "exclamationmark.triangle.fill")
                        .foregroundStyle(.orange)
                }
                .buttonStyle(.plain)
            }
        }
    }

    /// The only accent-coloured element, and only when there is something to act on.
    private var cleanupButton: some View {
        Button {
            show(.cleanup)
        } label: {
            HStack(spacing: 10) {
                Image(systemName: "sparkles").foregroundStyle(Color.accentColor)
                VStack(alignment: .leading, spacing: 1) {
                    Text(model.reclaimableBytes > 0 ? "Up to \(ByteFormat.string(model.reclaimableBytes)) can be freed" : "\(model.cleanupCount) groups to review")
                        .font(.callout.weight(.medium))
                    Text("Review duplicates").font(.caption).foregroundStyle(.secondary)
                }
                Spacer()
                Image(systemName: "chevron.right").font(.caption).foregroundStyle(.secondary)
            }
            .padding(10)
            .frame(maxWidth: .infinity, minHeight: 44)
            .background(Color.accentColor.opacity(0.10), in: RoundedRectangle(cornerRadius: 10))
            .overlay(RoundedRectangle(cornerRadius: 10).strokeBorder(Color.accentColor.opacity(0.35)))
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    private var footer: some View {
        HStack {
            Button("Open Pantry") { show(.overview) }
                .keyboardShortcut("o")
            SettingsLink {
                Image(systemName: "gearshape").frame(width: 28, height: 28)
            }
            .buttonStyle(.borderless)
            .help("Settings")
            .accessibilityLabel("Settings")
            Spacer()
            // Quit is on the opposite side from the primary button on purpose.
            Button("Quit") { NSApplication.shared.terminate(nil) }
                .keyboardShortcut("q")
        }
    }

    // MARK: Navigation

    private func show(_ item: SidebarItem, service: ModelService? = nil) {
        if let service {
            model.showInLibrary(service: service)
        } else {
            model.sidebarSelection = item
        }
        openWindow(id: "main")
        NSApp.activate(ignoringOtherApps: true)
    }
}

private struct MenuBarDownloadRow: View {
    @ObservedObject var job: DownloadJob

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack {
                Text(job.title).lineLimit(1).truncationMode(.middle)
                Spacer()
                Button {
                    job.cancel()
                } label: {
                    Image(systemName: "xmark.circle.fill").frame(width: 24, height: 24)
                }
                .buttonStyle(.borderless)
                .help("Cancel this download")
                .accessibilityLabel("Cancel download of \(job.title)")
            }
            if let fraction = job.progress.fraction {
                ProgressView(value: fraction)
            } else {
                ProgressView().progressViewStyle(.linear)
            }
            Text(progressText).font(.caption).foregroundStyle(.secondary)
        }
    }

    private var progressText: String {
        let p = job.progress
        guard let total = p.totalBytes, total > 0 else { return p.phase }
        return "\(p.phase) · \(ByteFormat.string(p.completedBytes)) of \(ByteFormat.string(total))"
    }
}
