import PantryCore
import SwiftUI

/// What sits in the menu bar: an icon, plus a short piece of text (total size, or download %).
struct MenuBarLabel: View {
    @EnvironmentObject private var model: AppModel
    @AppStorage(Prefs.showSizeInMenuBar) private var showSize = true

    private var hasScanned: Bool { model.lastScan != nil }

    var body: some View {
        let text = MenuBarTitle.text(
            hasScanned: hasScanned,
            showSize: showSize,
            totalBytes: model.summary.totalBytes,
            runningDownloads: model.runningDownloadCount,
            downloadFraction: model.downloadFraction
        )
        HStack(spacing: 4) {
            Image(systemName: MenuBarTitle.symbolName(runningDownloads: model.runningDownloadCount))
            if let text {
                Text(text).monospacedDigit()
            }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(MenuBarTitle.accessibilityLabel(
            hasScanned: hasScanned,
            totalBytes: model.summary.totalBytes,
            runningDownloads: model.runningDownloadCount,
            downloadFraction: model.downloadFraction
        ))
    }
}
