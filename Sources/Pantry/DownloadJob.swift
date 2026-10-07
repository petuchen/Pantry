import Foundation
import PantryCore

/// One running (or finished) download, observable by the UI.
@MainActor
final class DownloadJob: ObservableObject, Identifiable {
    enum State: Equatable {
        case running
        case finished
        case failed(String)
        case cancelled
    }

    let id = UUID()
    let title: String
    let service: ModelService
    @Published var state: State = .running
    @Published var progress = DownloadProgress(phase: "Starting")
    var task: Task<Void, Never>?

    init(title: String, service: ModelService) {
        self.title = title
        self.service = service
    }

    var isRunning: Bool { state == .running }

    func cancel() {
        task?.cancel()
    }
}
