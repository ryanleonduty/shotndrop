import XCTest
import AppKit
@testable import ShotNDrop

final class PixelDesignTests: XCTestCase {
    func testFontRegistrationSucceeds() {
        let bundle = Bundle(for: type(of: self))
        // Try test bundle first; fall back to app bundle for host-based test runs.
        let ok = PixelDesign.Font.registerAll(bundle: bundle) ||
                 PixelDesign.Font.registerAll(bundle: Bundle.main)
        XCTAssertTrue(ok)
    }

    func testFontRegistrationIdempotent() {
        _ = PixelDesign.Font.registerAll(bundle: Bundle.main)
        XCTAssertTrue(PixelDesign.Font.registerAll(bundle: Bundle.main),
                      "Second call must be treated as success")
    }

    func testFontRoleFallbackToMonospaceOnMissingFamily() {
        // Verify NSFont path returns *some* NSFont even for a role whose
        // family is not registered — the fallback is `monospacedSystemFont`.
        let font = PixelDesign.Font.nsFace(.body, size: 14)
        XCTAssertNotNil(font)
        XCTAssertGreaterThan(font.pointSize, 0)
    }

    func testMotionShakeSequence() {
        let seq = PixelDesign.Motion.shakeOffsets()
        XCTAssertEqual(seq.count, PixelDesign.Motion.steppedShakeSteps)
        XCTAssertEqual(seq.first, PixelDesign.Motion.steppedShakeAmplitude)
        XCTAssertEqual(seq.last, 0)
    }

    func testGeometryConstants() {
        XCTAssertEqual(PixelDesign.Geometry.slotSize, 96)
        XCTAssertEqual(PixelDesign.Geometry.trayWidth, 240)
        XCTAssertEqual(PixelDesign.Geometry.trayRowHeight, 60)
    }
}
