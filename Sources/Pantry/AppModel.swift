import AppKit
import Foundation
import PantryCore
import SwiftUI

enum SidebarItem: String, CaseIterable, Identifiable, Hashable {
    case overview
    case library
    case cleanup
    case getModels

    var id: String { rawValue }

    var title: String {
        switch self {
        case .overview: return "Overview"
        case .library: return "Models"
        case .cleanup: return "Cleanup"
        case .getModels: return "Get Models"
        }
    }

    var symbolName: String {
        switch self {
        case .overview: return "chart.pie"
        case .library: return "shippingbox"
        case .cleanup: return "sparkles"
        case .getModels: return "arrow.down.circle"
        }
    }
}

/// Shown after a removal finishes (the "end" moment of the flow: say exactly what happened).
struct RemovalReport: Identifiable {
    let id = UUID()
    let modelNames: [String]
    let result: RemovalResult
}

@MainActor
final class AppModel: ObservableObject {
    /// One model for the window, the menu bar item and the app delegate.
    static let shared = AppModel()

    enum ScanState: Equatable {
        case idle
        case scanning
        case finished
    }

    // MARK: Library state
    @Published private(set) var entries: [ModelEntry] = []
    @Published private(set) var summary: StorageSummary = .empty
    @Published private(set) var identicalGroups: [DuplicateGroup] = []
    @Published private(set) var similarGroups: [DuplicateGroup] = []
    @Published private(set) var scanState: ScanState = .idle
    @Published private(set) var isCheckingDuplicates = false
    @Published private(set) var warnings: [ScanWarning] = []
    @Published private(set) var scannedFolders: [ScannedFolder] = []
    @Published private(set) var diskAvailable: Int64?
    @Published private(set) var lastScan: Date?
    /// Average progress (0...1) of running downloads, for the menu bar. Nil when none report a total yet.
    @Published private(set) var downloadFraction: Double?
    private var autoRefreshTask: Task<Void, Never>?

    // MARK: Navigation and filters
    @Published var sidebarSelection: SidebarItem? = .overview
    @Published var librarySelection: Set<String> = []
    @Published var libraryServiceFilter: ModelService?
    @Published var libraryCategoryFilter: ModelCategory?
    @Published var librarySearch = ""

    // MARK: Settings
    @Published var customFolders: [CustomFolder] {
        didSet { persist() }
    }
    @Published private(set) var categoryOverrides: [String: ModelCategory]

    // MARK: Removal
    @Published var pendingRemoval: RemovalPlan?
    @Published var removalReport: RemovalReport?

    // MARK: Downloads
    @Published var downloads: [DownloadJob] = []

    init() {
        let settings = SettingsStore.load()
        self.customFolders = settings.customFolders
        self.categoryOverrides = settings.categoryOverrides
    }

    var locations: ScanLocations {
        ScanLocations.defaults(customFolders: customFolders)
    }

    var hasHuggingFaceToken: Bool { HuggingFaceClient().hasToken }

    /// Bytes that keeping a single copy of every identical file would free.
    var reclaimableBytes: Int64 {
        identicalGroups.reduce(Int64(0)) { $0 + ($1.reclaimableBytes ?? 0) }
    }

    var cleanupCount: Int { identicalGroups.count + similarGroups.count }

    var runningDownloadCount: Int { downloads.filter { $0.isRunning }.count }

    // MARK: Scanning

    func refresh() async {
        guard scanState != .scanning else { return }
        scanState = .scanning
        let currentLocations = locations
        let result = await ModelLibrary.scan(locations: currentLocations)
        apply(result)
        scanState = .finished
        lastScan = Date()
        diskAvailable = DiskSpace.availableBytes(at: FileManager.default.homeDirectoryForCurrentUser)
        await findDuplicates()
    }

    private func apply(_ result: ScanResult) {
        entries = result.entries.map { entry in
            var copy = entry
            if let override = categoryOverrides[entry.id] { copy.category = override }
            return copy
        }
        summary = StorageSummary.make(from: entries)
        warnings = result.warnings
        scannedFolders = result.folders
        librarySelection = librarySelection.intersection(Set(entries.map { $0.id }))
    }

    func findDuplicates() async {
        isCheckingDuplicates = true
        let snapshot = entries
        let found = await Task.detached(priority: .utility) { () -> ([DuplicateGroup], [DuplicateGroup]) in
            let identical = DuplicateDetector().findIdentical(in: snapshot)
            let similar = DuplicateDetector.findSimilar(in: snapshot, excluding: identical)
            return (identical, similar)
        }.value
        identicalGroups = found.0
        similarGroups = found.1
        isCheckingDuplicates = false
    }

    // MARK: Categories

    func setCategory(_ category: ModelCategory, for ids: Set<String>) {
        for id in ids { categoryOverrides[id] = category }
        entries = entries.map { entry in
            guard ids.contains(entry.id) else { return entry }
            var copy = entry
            copy.category = category
            return copy
        }
        summary = StorageSummary.make(from: entries)
        persist()
    }

    private func persist() {
        SettingsStore.save(PersistedSettings(customFolders: customFolders, categoryOverrides: categoryOverrides))
    }

    // MARK: Removal

    func requestRemoval(of ids: Set<String>) {
        let selected = entries.filter { ids.contains($0.id) }
        guard !selected.isEmpty else { return }
        pendingRemoval = RemovalPlanner.plan(removing: selected, from: entries)
    }

    func cancelRemoval() {
        pendingRemoval = nil
    }

    func confirmRemoval(mode: RemovalMode) async {
        guard let plan = pendingRemoval else { return }
        pendingRemoval = nil
        let roots = locations.allRoots
        let result = await Task.detached(priority: .userInitiated) {
            RemovalExecutor(allowedRoots: roots).execute(plan, mode: mode)
        }.value
        removalReport = RemovalReport(modelNames: plan.entries.map { $0.name }, result: result)
        await refresh()
    }

    // MARK: Downloads

    private func isCancellation(_ error: Error) -> Bool {
        error is CancellationError || (error as? URLError)?.code == .cancelled
    }

    private func finish(_ job: DownloadJob, with error: Error?) {
        if let error {
            job.state = isCancellation(error) ? .cancelled : .failed(error.localizedDescription)
        } else {
            job.state = .finished
        }
        updateDownloadProgress()
    }

    /// Free space on the volume that will hold `folder`, walking up to the nearest folder that exists.
    private func availableSpace(for folder: URL) -> Int64? {
        var candidate = folder
        while !FileManager.default.fileExists(atPath: candidate.path) && candidate.pathComponents.count > 1 {
            candidate = candidate.deletingLastPathComponent()
        }
        return DiskSpace.availableBytes(at: candidate)
    }

    func startOllamaPull(name: String) {
        let job = DownloadJob(title: name, service: .ollama)
        downloads.insert(job, at: 0)
        job.task = Task { [weak self] in
            guard let self else { return }
            do {
                try await OllamaPuller().pull(model: name) { progress in
                    Task { @MainActor in
                        job.progress = progress
                        self.updateDownloadProgress()
                    }
                }
                self.finish(job, with: nil)
                await self.refresh()
            } catch {
                self.finish(job, with: error)
            }
        }
    }

    func startRepoDownload(_ details: HFRepoDetails, service: ModelService) {
        let job = DownloadJob(title: details.id, service: service)
        downloads.insert(job, at: 0)
        let hub = locations.huggingFaceHub
        if let free = availableSpace(for: hub), details.totalBytes > free {
            job.state = .failed(DownloadError.notEnoughSpace(needed: details.totalBytes, available: free).localizedDescription)
            return
        }
        let downloader = HuggingFaceDownloader(client: HuggingFaceClient(), layout: HFCacheLayout(hubRoot: hub))
        job.task = Task { [weak self] in
            guard let self else { return }
            do {
                try await downloader.downloadRepo(details) { progress in
                    Task { @MainActor in
                        job.progress = progress
                        self.updateDownloadProgress()
                    }
                }
                self.finish(job, with: nil)
                await self.refresh()
            } catch {
                self.finish(job, with: error)
            }
        }
    }

    func startGGUFDownload(repo: String, revision: String, file: HFRepoFile) {
        let job = DownloadJob(title: file.path, service: .llamaCpp)
        downloads.insert(job, at: 0)
        let folder = locations.downloadFolder(for: .llamaCpp)
        if let free = availableSpace(for: folder), file.size > free {
            job.state = .failed(DownloadError.notEnoughSpace(needed: file.size, available: free).localizedDescription)
            return
        }
        let downloader = HuggingFaceDownloader(client: HuggingFaceClient(), layout: HFCacheLayout(hubRoot: locations.huggingFaceHub))
        job.task = Task { [weak self] in
            guard let self else { return }
            do {
                _ = try await downloader.downloadSingleFile(repo: repo, revision: revision, file: file, into: folder) { progress in
                    Task { @MainActor in
                        job.progress = progress
                        self.updateDownloadProgress()
                    }
                }
                self.finish(job, with: nil)
                await self.refresh()
            } catch {
                self.finish(job, with: error)
            }
        }
    }

    func dismiss(_ job: DownloadJob) {
        downloads.removeAll { $0.id == job.id }
    }

    // MARK: Background refresh (menu bar keeps the numbers current without the window open)

    /// Rescans only if the last scan is older than `maxAge`, so opening the popover is instant
    /// when the numbers are fresh.
    func refreshIfStale(maxAge: TimeInterval = 30) async {
        if let lastScan, Date().timeIntervalSince(lastScan) < maxAge { return }
        await refresh()
    }

    func startAutoRefresh(every seconds: TimeInterval = 600) {
        guard autoRefreshTask == nil else { return }
        autoRefreshTask = Task { [weak self] in
            while !Task.isCancelled {
                try? await Task.sleep(nanoseconds: UInt64(seconds * 1_000_000_000))
                await self?.refresh()
            }
        }
    }

    func updateDownloadProgress() {
        let fractions = downloads.filter { $0.isRunning }.compactMap { $0.progress.fraction }
        downloadFraction = fractions.isEmpty ? nil : fractions.reduce(0, +) / Double(fractions.count)
    }

    // MARK: Navigation helpers

    func showInLibrary(service: ModelService? = nil, category: ModelCategory? = nil, selecting ids: Set<String> = []) {
        libraryServiceFilter = service
        libraryCategoryFilter = category
        librarySearch = ""
        librarySelection = ids
        sidebarSelection = .library
    }
}
