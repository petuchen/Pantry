import XCTest
@testable import PantryCore

final class MenuBarTitleTests: XCTestCase {
    private func title(
        scanned: Bool = true, showSize: Bool = true, bytes: Int64 = 42_300_000_000,
        downloads: Int = 0, fraction: Double? = nil
    ) -> String? {
        MenuBarTitle.text(hasScanned: scanned, showSize: showSize, totalBytes: bytes, runningDownloads: downloads, downloadFraction: fraction)
    }

    func testShowsTotalSizeWhenIdle() {
        let text = title()
        XCTAssertNotNil(text)
        XCTAssertTrue(text!.contains("GB"))
    }

    func testSizeIsRoundedUpToWholeUnits() {
        XCTAssertEqual(title(bytes: 177_770_000_000), "178 GB")
        XCTAssertEqual(title(bytes: 177_000_000_001), "178 GB")
        XCTAssertEqual(title(bytes: 42_300_000_000), "43 GB")
        XCTAssertEqual(title(bytes: 999_900_000), "1 GB", "rounding up to 1000 MB moves to the next unit")
        XCTAssertEqual(title(bytes: 1_200_000_000_000), "2 TB")
    }

    func testIconOnlyWhenSizeIsTurnedOffOrNotScannedYet() {
        XCTAssertNil(title(showSize: false))
        XCTAssertNil(title(scanned: false), "never flash 0 bytes before the first scan")
    }

    func testDownloadProgressWinsOverSize() {
        XCTAssertEqual(title(downloads: 1, fraction: 0.426), "43%")
        XCTAssertEqual(title(showSize: false, downloads: 2, fraction: 0.5), "50%", "progress shows even if the size is hidden")
    }

    func testDownloadWithoutKnownFractionShowsIconOnly() {
        XCTAssertNil(title(downloads: 1, fraction: nil))
    }

    func testPercentIsClamped() {
        XCTAssertEqual(title(downloads: 1, fraction: 1.7), "100%")
        XCTAssertEqual(title(downloads: 1, fraction: -0.2), "0%")
    }

    func testSymbolFollowsDownloadState() {
        XCTAssertEqual(MenuBarTitle.symbolName(runningDownloads: 0), "shippingbox")
        XCTAssertEqual(MenuBarTitle.symbolName(runningDownloads: 2), "arrow.down.circle")
    }

    func testAccessibilityLabelsAreSpokenSentences() {
        XCTAssertEqual(MenuBarTitle.accessibilityLabel(hasScanned: false, totalBytes: 0, runningDownloads: 0, downloadFraction: nil), "Pantry, scanning models")
        XCTAssertTrue(MenuBarTitle.accessibilityLabel(hasScanned: true, totalBytes: 5_000_000_000, runningDownloads: 0, downloadFraction: nil).hasPrefix("Pantry, models use"))
        XCTAssertEqual(MenuBarTitle.accessibilityLabel(hasScanned: true, totalBytes: 1, runningDownloads: 1, downloadFraction: 0.25), "Pantry, 1 download in progress, 25 percent")
        XCTAssertEqual(MenuBarTitle.accessibilityLabel(hasScanned: true, totalBytes: 1, runningDownloads: 3, downloadFraction: nil), "Pantry, 3 downloads in progress")
    }
}
