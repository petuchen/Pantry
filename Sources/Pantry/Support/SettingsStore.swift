import Foundation
import PantryCore

/// What Pantry remembers between launches. Decoding is lenient: a field added in a later
/// version never makes an older settings file unreadable.
struct PersistedSettings: Codable {
    var customFolders: [CustomFolder] = []
    var categoryOverrides: [String: ModelCategory] = [:]

    init(customFolders: [CustomFolder] = [], categoryOverrides: [String: ModelCategory] = [:]) {
        self.customFolders = customFolders
        self.categoryOverrides = categoryOverrides
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        customFolders = (try? c.decode([CustomFolder].self, forKey: .customFolders)) ?? []
        categoryOverrides = (try? c.decode([String: ModelCategory].self, forKey: .categoryOverrides)) ?? [:]
    }

    enum CodingKeys: String, CodingKey {
        case customFolders, categoryOverrides
    }
}

enum SettingsStore {
    static var fileURL: URL {
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
            ?? FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent("Library/Application Support")
        return base.appendingPathComponent("Pantry/settings.json")
    }

    static func load() -> PersistedSettings {
        guard let data = try? Data(contentsOf: fileURL),
              let settings = try? JSONDecoder().decode(PersistedSettings.self, from: data) else {
            return PersistedSettings()
        }
        return settings
    }

    static func save(_ settings: PersistedSettings) {
        let url = fileURL
        try? FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        if let data = try? encoder.encode(settings) {
            try? data.write(to: url, options: .atomic)
        }
    }
}
