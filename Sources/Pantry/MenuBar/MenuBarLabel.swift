import AppKit
import PantryCore
import SwiftUI

/// The bundled cat glyph (resources/MenuBarGlyph*.png) as a template image, so macOS tints it
/// for light/dark menu bars. Nil when running outside the app bundle (e.g. `swift run`).
enum MenuBarGlyph {
    static let image: NSImage? = {
        guard let url1x = Bundle.main.url(forResource: "MenuBarGlyph", withExtension: "png"),
              let image = NSImage(contentsOf: url1x) else { return nil }
        if let url2x = Bundle.main.url(forResource: "MenuBarGlyph@2x", withExtension: "png"),
           let data = try? Data(contentsOf: url2x),
           let rep = NSBitmapImageRep(data: data) {
            rep.size = NSSize(width: 18, height: 18)
            image.addRepresentation(rep)
        }
        image.size = NSSize(width: 18, height: 18)
        image.isTemplate = true
        return image
    }()
}

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
            if model.runningDownloadCount == 0, let glyph = MenuBarGlyph.image {
                Image(nsImage: glyph)
            } else {
                Image(systemName: MenuBarTitle.symbolName(runningDownloads: model.runningDownloadCount))
            }
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
