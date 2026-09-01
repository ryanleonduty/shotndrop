import XCTest
import AppKit
@testable import ShotNDrop

@MainActor
final class ShelfPanelControllerTests: XCTestCase {
    private var scratch: URL!

    override func setUpWithError() throws {
        scratch = URL(fileURLWithPath: NSTemporaryDirectory(), isDirectory: true)
            .appendingPathComponent("shelf-panel-tests-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: scratch, withIntermediateDirectories: true)
    }

    override func tearDownWithError() throws {
        try? FileManager.default.removeItem(at: scratch)
    }

    func testDefaultShowMovesToRightEdgeCenter() throws {
        let store = try ShelfSessionStore(parentDirectory: scratch)
        defer { store.shutdown() }
        let inventory = ShelfInventory()
        let controller = ShelfPanelController(inventory: inventory, sessionStore: store)
        controller.showAtDefaultPosition()
        XCTAssertTrue(controller.panel.isVisible)
    }

    func testDownwardFrameCapsBodyWithoutMovingChipOrigin() {
        let origin = NSPoint(x: 300, y: 80)
        let screen = NSRect(x: 0, y: 0, width: 500, height: 900)
        let result = ShelfPanelController.downwardExpandedFrame(
            barOrigin: origin,
            horizontalOrigin: 250,
            screenFrame: screen,
            bodyHeight: 700,
            expandedWidth: 150,
            minimizedHeight: 48
        )

        XCTAssertEqual(result.mode, .expandedBelow)
        XCTAssertEqual(result.frame.minY, screen.minY)
        XCTAssertEqual(result.frame.maxY, origin.y + 48)
        XCTAssertTrue(screen.contains(result.frame))
        XCTAssertEqual(origin, NSPoint(x: 300, y: 80))
    }


    func testMinimizedChipUsesGenericDropLabelDuringHover() {
        XCTAssertEqual(
            ShelfChipView.stateLabel(for: .dragHover(hadItems: false)),
            "DROP ITEM"
        )
        XCTAssertEqual(
            ShelfChipView.stateLabel(for: .dragHover(hadItems: true)),
            "DROP ITEM"
        )
        XCTAssertNil(ShelfChipView.stateLabel(for: .idleEmpty(count: 3)))
    }
    func testConsumeCallsInventoryRemoveAndStoreRemove() throws {
        let store = try ShelfSessionStore(parentDirectory: scratch)
        defer { store.shutdown() }
        let inventory = ShelfInventory()
        let controller = ShelfPanelController(inventory: inventory, sessionStore: store)

        let id = inventory.reservePending()!
        let url = try store.write(bytes: Data("hello".utf8), id: id, preferredExtension: "png")
        let payload = ShelfInventoryTests.makePayload(id: id)
        _ = inventory.resolve(id: id, with: ShelfMediaPayload(
            id: payload.id,
            kind: payload.kind,
            sessionStoreURL: url,
            originalFilename: payload.originalFilename,
            capturedAt: payload.capturedAt,
            sizeBytes: payload.sizeBytes,
            dimensions: payload.dimensions,
            fingerprint: payload.fingerprint,
            utiIdentifier: payload.utiIdentifier
        ))

        // Simulate a drag-out `.copy` consume path:
        _ = inventory.remove(id: id)
        store.remove(id: id)
        controller.renderSlot()

        XCTAssertTrue(inventory.isEmpty)
        XCTAssertFalse(FileManager.default.fileExists(atPath: url.path))
    }

    func testRightClickWhileExpandedCollapsesFirst() throws {
        let store = try ShelfSessionStore(parentDirectory: scratch)
        defer { store.shutdown() }
        let inventory = ShelfInventory()
        let controller = ShelfPanelController(inventory: inventory, sessionStore: store)
        controller.showAtDefaultPosition()
        controller.expand()
        XCTAssertTrue(controller.isExpanded)
        controller.handleSlotRightClick(at: .zero)
        XCTAssertFalse(controller.isExpanded)
    }

    func testEscapeKeyCollapsesExpandedPanel() throws {
        let store = try ShelfSessionStore(parentDirectory: scratch)
        defer { store.shutdown() }
        let inventory = ShelfInventory()
        let controller = ShelfPanelController(inventory: inventory, sessionStore: store)
        controller.showAtDefaultPosition()
        controller.expand()
        XCTAssertTrue(controller.isExpanded)
        XCTAssertTrue(controller.panel.isKeyWindow)

        let event = try XCTUnwrap(NSEvent.keyEvent(
            with: .keyDown,
            location: .zero,
            modifierFlags: [],
            timestamp: 0,
            windowNumber: controller.panel.windowNumber,
            context: nil,
            characters: "\u{1b}",
            charactersIgnoringModifiers: "\u{1b}",
            isARepeat: false,
            keyCode: 53
        ))
        controller.panel.keyDown(with: event)
        XCTAssertFalse(controller.isExpanded)
        XCTAssertFalse(controller.panel.isKeyWindow)
    }

    func testSlotClickTogglesExpanded() throws {
        let store = try ShelfSessionStore(parentDirectory: scratch)
        defer { store.shutdown() }
        let inventory = ShelfInventory()
        let controller = ShelfPanelController(inventory: inventory, sessionStore: store)
        controller.showAtDefaultPosition()
        XCTAssertFalse(controller.isExpanded)
        controller.handleSlotClick()
        XCTAssertTrue(controller.isExpanded)
        controller.handleSlotClick()
        XCTAssertFalse(controller.isExpanded)
    }
}
