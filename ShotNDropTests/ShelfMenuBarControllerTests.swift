import XCTest
@testable import ShotNDrop

@MainActor
final class ShelfMenuBarControllerTests: XCTestCase {
    func testMenuTitles() throws {
        let scratch = URL(fileURLWithPath: NSTemporaryDirectory(), isDirectory: true)
            .appendingPathComponent("menubar-tests-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: scratch, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: scratch) }

        let store = try ShelfSessionStore(parentDirectory: scratch)
        defer { store.shutdown() }
        let inventory = ShelfInventory()
        let panel = ShelfPanelController(inventory: inventory, sessionStore: store)
        let menu = ShelfMenuBarController(panelController: panel)

        XCTAssertEqual(menu.menuTitles, ["Show", "Clear", "Check for Updates", "Quit"])

        panel.showAtDefaultPosition()
        XCTAssertEqual(menu.menuTitles.first, "Hide")
        panel.hide()
        XCTAssertEqual(menu.menuTitles.first, "Show")
}
    func testClearAndToggleActionsDispatchThroughObjectiveCEntryPoints() throws {
        let scratch = URL(fileURLWithPath: NSTemporaryDirectory(), isDirectory: true)
            .appendingPathComponent("menubar-action-tests-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: scratch, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: scratch) }

        let store = try ShelfSessionStore(parentDirectory: scratch)
        defer { store.shutdown() }
        let panel = ShelfPanelController(inventory: ShelfInventory(), sessionStore: store)
        let menuBar = ShelfMenuBarController(panelController: panel)

        XCTAssertTrue(NSApp.sendAction(Selector("clear"), to: menuBar, from: nil))

        XCTAssertTrue(NSApp.sendAction(Selector("toggleVisibility"), to: menuBar, from: nil))
        XCTAssertTrue(panel.panel.isVisible)

        XCTAssertTrue(NSApp.sendAction(Selector("toggleVisibility"), to: menuBar, from: nil))
        XCTAssertFalse(panel.panel.isVisible)
    }
}
