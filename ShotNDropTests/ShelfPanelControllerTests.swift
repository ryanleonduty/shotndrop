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

    func testDraggedOriginKeepsPanelWithinScreenBounds() {
        let screen = NSRect(x: 100, y: 200, width: 800, height: 600)
        let size = NSSize(width: 120, height: 300)

        let topLeft = ShelfPanelController.clampedOrigin(
            NSPoint(x: -500, y: 999),
            panelSize: size,
            screenFrame: screen
        )
        let bottomRight = ShelfPanelController.clampedOrigin(
            NSPoint(x: 999, y: -500),
            panelSize: size,
            screenFrame: screen
        )

        XCTAssertEqual(topLeft, NSPoint(x: 100, y: 500))
        XCTAssertEqual(bottomRight, NSPoint(x: 780, y: 200))
    }

    func testOversizedPanelClampsToVisibleTopAndRightEdges() {
        let screen = NSRect(x: 100, y: 200, width: 800, height: 600)
        let result = ShelfPanelController.clampedOrigin(
            NSPoint(x: 0, y: 0),
            panelSize: NSSize(width: 1_000, height: 900),
            screenFrame: screen
        )

        XCTAssertEqual(result.x, -100)
        XCTAssertEqual(result.y, -100)
        XCTAssertEqual(result.x + 1_000, screen.maxX)
        XCTAssertEqual(result.y + 900, screen.maxY)
    }

    func testDragAnchorProjectionPreservesTopEdgeWhenTrayResizesEitherDirection() {
        XCTAssertEqual(
            ShelfPanelController.dragAnchorYAdjustment(
                oldHeight: 800,
                targetHeight: 240,
                anchorsTopEdge: true
            ),
            560
        )
        XCTAssertEqual(
            ShelfPanelController.dragAnchorYAdjustment(
                oldHeight: 240,
                targetHeight: 800,
                anchorsTopEdge: true
            ),
            -560
        )
        XCTAssertEqual(
            ShelfPanelController.dragAnchorYAdjustment(
                oldHeight: 800,
                targetHeight: 240,
                anchorsTopEdge: false
            ),
            0
        )
    }

    func testProjectedDragOriginUsesTargetSizeOnVerticallyOffsetDisplay() {
        let result = ShelfPanelController.projectedDragOrigin(
            mouseGlobal: NSPoint(x: 500, y: -100),
            localAnchor: NSPoint(x: 50, y: 700),
            oldPanelSize: NSSize(width: 150, height: 800),
            targetPanelSize: NSSize(width: 150, height: 240),
            screenFrame: NSRect(x: 0, y: -300, width: 800, height: 400),
            anchorsTopEdge: true
        )

        XCTAssertEqual(result, NSPoint(x: 450, y: -240))
    }

    func testFractionalDragProjectionDoesNotAccumulateIntegerFrameRounding() {
        let screen = NSRect(x: 0, y: 0, width: 1_500, height: 900)
        let anchor = NSPoint(x: 23.969, y: 38.590)
        let panelSize = NSSize(width: 90, height: 48)
        var simulatedFrameOrigin = NSPoint(x: 1_000, y: 400)

        for index in 0..<40 {
            let mouse = NSPoint(
                x: 1_000 + anchor.x + CGFloat(index) * 1.37,
                y: 400 + anchor.y + CGFloat(index) * 0.83
            )
            let projected = ShelfPanelController.projectedDragOrigin(
                mouseGlobal: mouse,
                localAnchor: anchor,
                oldPanelSize: panelSize,
                targetPanelSize: panelSize,
                screenFrame: screen,
                anchorsTopEdge: false
            )
            XCTAssertEqual(projected.x, 1_000 + CGFloat(index) * 1.37, accuracy: 0.001)
            XCTAssertEqual(projected.y, 400 + CGFloat(index) * 0.83, accuracy: 0.001)
            simulatedFrameOrigin = NSPoint(x: projected.x.rounded(), y: projected.y.rounded())
        }

        XCTAssertEqual(simulatedFrameOrigin.x, 1_053, accuracy: 0.5)
        XCTAssertEqual(simulatedFrameOrigin.y, 432, accuracy: 0.5)
    }

    func testDragAnchorRefreshSkipsFractionalRoundingButRefreshesAtClamp() {
        let size = NSSize(width: 90, height: 48)
        XCTAssertFalse(
            ShelfPanelController.shouldRefreshDragAnchor(
                proposedOrigin: NSPoint(x: 100.4, y: 200.6),
                clampedOrigin: NSPoint(x: 100.4, y: 200.6),
                oldPanelSize: size,
                targetPanelSize: size
            )
        )
        XCTAssertTrue(
            ShelfPanelController.shouldRefreshDragAnchor(
                proposedOrigin: NSPoint(x: -2, y: 200),
                clampedOrigin: NSPoint(x: 0, y: 200),
                oldPanelSize: size,
                targetPanelSize: size
            )
        )
        XCTAssertTrue(
            ShelfPanelController.shouldRefreshDragAnchor(
                proposedOrigin: NSPoint(x: 100.4, y: 200.6),
                clampedOrigin: NSPoint(x: 100.4, y: 200.6),
                oldPanelSize: size,
                targetPanelSize: NSSize(width: 90, height: 240)
            )
        )
    }

    func testDraggingExpandedPanelAcrossShorterDisplayResizesAndCollapsesToHeader() throws {
        let store = try ShelfSessionStore(parentDirectory: scratch)
        defer { store.shutdown() }
        let inventory = ShelfInventory()
        let controller = ShelfPanelController(inventory: inventory, sessionStore: store)

        for index in 0..<20 {
            let id = try XCTUnwrap(inventory.reservePending())
            let data = Data(repeating: UInt8(index), count: 128)
            let payload = ShelfMediaPayload(
                id: id,
                kind: .image,
                sessionStoreURL: URL(fileURLWithPath: "/tmp/\(id.uuidString).png"),
                originalFilename: "\(id.uuidString).png",
                capturedAt: Date(),
                sizeBytes: data.count,
                dimensions: .init(width: 100, height: 100),
                fingerprint: .compute(from: data),
                utiIdentifier: "public.png"
            )
            XCTAssertTrue(inventory.resolve(id: id, with: payload))
        }

        controller.showAtDefaultPosition()
        controller.expand(animated: false, makeKey: false)

        let shorterScreen = NSRect(x: 0, y: 0, width: 800, height: 400)
        let draggedOrigin = NSPoint(x: 300, y: 100)
        let expectedSize = controller.panelSizeForDrag(screenFrame: shorterScreen)
        controller.handleSlotDragMoved(
            to: draggedOrigin,
            screenFrame: shorterScreen,
            targetSize: expectedSize
        )

        XCTAssertEqual(controller.panel.frame.origin, draggedOrigin)
        XCTAssertEqual(controller.panel.frame.size, expectedSize)

        XCTAssertTrue(shorterScreen.contains(controller.panel.frame))

        let chipWidth = controller.minimizedFrame.width
        let expectedChipX = [draggedOrigin.x, draggedOrigin.x + expectedSize.width - chipWidth]
        let expectedChipY = draggedOrigin.y + expectedSize.height - controller.minimizedFrame.height

        controller.collapse(animated: false)
        XCTAssertTrue(expectedChipX.contains(controller.panel.frame.minX))
        XCTAssertEqual(controller.panel.frame.minY, expectedChipY)
        XCTAssertEqual(controller.panel.frame.height, 48)
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
