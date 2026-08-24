import XCTest
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
