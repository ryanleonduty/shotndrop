import XCTest
@testable import ShotNDrop

final class TrayAnchorTests: XCTestCase {
    func testPrefersBelowTrailingWhenItFits() {
        let slot = CGRect(x: 400, y: 400, width: 96, height: 96)
        let screen = CGRect(x: 0, y: 0, width: 1440, height: 900)
        let tray = CGSize(width: 240, height: 400)
        XCTAssertEqual(TrayAnchor.resolve(slotFrame: slot, screenFrame: screen, traySize: tray),
                       .belowTrailing)
    }

    func testFallsBackToAboveWhenBelowClips() {
        let slot = CGRect(x: 400, y: 50, width: 96, height: 96)
        let screen = CGRect(x: 0, y: 0, width: 1440, height: 900)
        let tray = CGSize(width: 240, height: 400)
        let anchor = TrayAnchor.resolve(slotFrame: slot, screenFrame: screen, traySize: tray)
        XCTAssertTrue(anchor == .aboveTrailing || anchor == .aboveLeading, "got \(anchor)")
    }

    func testFallsBackToLeadingWhenTrailingClips() {
        let slot = CGRect(x: 20, y: 400, width: 96, height: 96)
        let screen = CGRect(x: 0, y: 0, width: 1440, height: 900)
        let tray = CGSize(width: 240, height: 400)
        // belowTrailing origin.x = 20 + 96 - 240 = -124 < 0 → clips
        // belowLeading  origin.x = 20 → fits
        XCTAssertEqual(TrayAnchor.resolve(slotFrame: slot, screenFrame: screen, traySize: tray),
                       .belowLeading)
    }

    func testDegradesToBelowTrailingWhenNothingFits() {
        let slot = CGRect(x: 0, y: 0, width: 96, height: 96)
        let screen = CGRect(x: 0, y: 0, width: 100, height: 100)
        let tray = CGSize(width: 5000, height: 5000)
        XCTAssertEqual(TrayAnchor.resolve(slotFrame: slot, screenFrame: screen, traySize: tray),
                       .belowTrailing)
    }
}
