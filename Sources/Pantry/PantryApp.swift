import AppKit
import SwiftUI

/// A SwiftPM executable starts as a background process; this makes it a normal foreground app
/// (or a menu-bar-only app, if the user hid the Dock icon). In a real .app bundle it is mostly a no-op.
final class AppDelegate: NSObject, NSApplicationDelegate {
    func applicationDidFinishLaunching(_ notification: Notification) {
        // Never end up with no way back in: with the menu bar item off, the Dock icon stays on.
        let showInDock = DockPolicy.storedShowInDock || !DockPolicy.storedShowMenuBar
        DockPolicy.apply(showInDock: showInDock)
        NSApp.activate(ignoringOtherApps: true)

        // Scan at launch and keep numbers fresh, whether or not the window is ever opened.
        Task { @MainActor in
            AppModel.shared.startAutoRefresh()
            await AppModel.shared.refresh()
        }
    }

    /// Closing the window leaves Pantry running in the menu bar.
    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        false
    }
}

@main
struct PantryApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate
    @StateObject private var model = AppModel.shared
    @AppStorage(Prefs.showMenuBar) private var showMenuBar = true

    var body: some Scene {
        Window("Pantry", id: "main") {
            RootView()
                .environmentObject(model)
                .frame(minWidth: 960, minHeight: 600)
                .task { await model.refreshIfStale() }
        }
        .commands {
            CommandGroup(after: .newItem) {
                Button("Rescan Models") { Task { await model.refresh() } }
                    .keyboardShortcut("r", modifiers: .command)
            }
            CommandMenu("Go") {
                ForEach(Array(SidebarItem.allCases.enumerated()), id: \.element) { index, item in
                    Button(item.title) { model.sidebarSelection = item }
                        .keyboardShortcut(KeyEquivalent(Character(String(index + 1))), modifiers: .command)
                }
            }
        }

        MenuBarExtra(isInserted: $showMenuBar) {
            MenuBarContent()
                .environmentObject(model)
        } label: {
            MenuBarLabel()
                .environmentObject(model)
        }
        .menuBarExtraStyle(.window)

        Settings {
            SettingsView()
                .environmentObject(model)
        }
    }
}
