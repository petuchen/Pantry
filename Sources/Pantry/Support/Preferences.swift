import AppKit

/// UserDefaults keys shared by the app, the menu bar item and Settings (@AppStorage uses the same keys).
enum Prefs {
    static let showMenuBar = "showMenuBarItem"
    static let showSizeInMenuBar = "showSizeInMenuBar"
    static let showInDock = "showInDock"
}

enum DockPolicy {
    /// Hidden Dock icon = "accessory" app: lives in the menu bar only, no Dock tile or app menu.
    static func apply(showInDock: Bool) {
        NSApp.setActivationPolicy(showInDock ? .regular : .accessory)
    }

    static var storedShowInDock: Bool {
        UserDefaults.standard.object(forKey: Prefs.showInDock) as? Bool ?? true
    }

    static var storedShowMenuBar: Bool {
        UserDefaults.standard.object(forKey: Prefs.showMenuBar) as? Bool ?? true
    }
}
