import XCTest
@testable import ShotNDrop

final class OverlayPanelControllerTests: XCTestCase {
    // MARK: - Screen selection

    func testCursorInsideAScreenPicksIt() {
        let a = CGRect(x: 0, y: 0, width: 1440, height: 900)
        let b = CGRect(x: 1440, y: 200, width: 1440, height: 900)
        let picked = OverlayGeometry.screen(forCursor: CGPoint(x: 1600, y: 400), in: [a, b])
        XCTAssertEqual(picked, b)
    }

    func testCursorOffScreenFallsBackToFirst() {
        let a = CGRect(x: 0, y: 0, width: 1440, height: 900)
        let b = CGRect(x: 1440, y: 0, width: 1440, height: 900)
        let picked = OverlayGeometry.screen(forCursor: CGPoint(x: 5000, y: 5000), in: [a, b])
        XCTAssertEqual(picked, a)
    }

    func testNoScreensReturnsNil() {
        XCTAssertNil(OverlayGeometry.screen(forCursor: CGPoint(x: 0, y: 0), in: []))
    }

    // MARK: - Frame geometry

    func testTopTrailingIsWithinVisibleFrame() {
        let visible = CGRect(x: 100, y: 100, width: 1200, height: 800)
        let size = CGSize(width: 320, height: 240)
        let frame = OverlayGeometry.frame(size: size, corner: .topTrailing, visibleFrame: visible)
        XCTAssertTrue(visible.contains(frame),
                      "frame \(frame) not fully inside \(visible)")
        // Top-trailing: closer to maxX/maxY.
        XCTAssertEqual(frame.maxX, visible.maxX - OverlayGeometry.visibleInset, accuracy: 0.5)
        XCTAssertEqual(frame.maxY, visible.maxY - OverlayGeometry.visibleInset, accuracy: 0.5)
    }

    func testAllCornersStayInside() {
        let visible = CGRect(x: 50, y: 40, width: 800, height: 600)
        let size = CGSize(width: 300, height: 200)
        for corner in [OverlayCorner.topLeading, .topTrailing, .bottomLeading, .bottomTrailing] {
            let frame = OverlayGeometry.frame(size: size, corner: corner, visibleFrame: visible)
            XCTAssertTrue(visible.contains(frame), "\(corner) placed \(frame) outside \(visible)")
        }
    }

    func testFrameShrinksToFitTinyScreen() {
        let visible = CGRect(x: 0, y: 0, width: 200, height: 150)
        let size = CGSize(width: 500, height: 400)
        let frame = OverlayGeometry.frame(size: size, corner: .topTrailing, visibleFrame: visible)
        XCTAssertLessThanOrEqual(frame.maxX, visible.maxX)
        XCTAssertLessThanOrEqual(frame.maxY, visible.maxY)
        XCTAssertGreaterThanOrEqual(frame.minX, visible.minX)
        XCTAssertGreaterThanOrEqual(frame.minY, visible.minY)
    }

    // MARK: - Visibility state machine

    func testShowIncrementsGeneration() {
        var state = VisibilityState()
        let g0 = state.timerGeneration
        state = VisibilityTransition.onShow(state, at: Date(), cause: .newItem)
        XCTAssertTrue(state.isVisible)
        XCTAssertEqual(state.timerGeneration, g0 &+ 1)

        state = VisibilityTransition.onShow(state, at: Date(), cause: .newItem)
        XCTAssertEqual(state.timerGeneration, g0 &+ 2)
    }

    func testHideKeepsGeneration() {
        var state = VisibilityState()
        state = VisibilityTransition.onShow(state, at: Date(), cause: .menuReopen)
        let g = state.timerGeneration
        state = VisibilityTransition.onHide(state)
        XCTAssertFalse(state.isVisible)
        XCTAssertEqual(state.timerGeneration, g)
    }

    func testAutoHideOnlyFiresForCurrentGeneration() {
        var state = VisibilityState()
        state = VisibilityTransition.onShow(state, at: Date(), cause: .newItem)
        let fired = state.timerGeneration
        state = VisibilityTransition.onShow(state, at: Date(), cause: .newItem)
        XCTAssertFalse(
            VisibilityTransition.shouldAutoHide(currentGeneration: state.timerGeneration, firedGeneration: fired)
        )
        XCTAssertTrue(
            VisibilityTransition.shouldAutoHide(currentGeneration: state.timerGeneration, firedGeneration: state.timerGeneration)
        )
    }
}
