import XCTest
@testable import ShotNDrop

final class UpdateCheckerTests: XCTestCase {
    func testNormalizesReleaseTags() {
        XCTAssertEqual(UpdateChecker.normalizedVersion(" v0.1.3\n"), "0.1.3")
        XCTAssertEqual(UpdateChecker.normalizedVersion("0.1.3"), "0.1.3")
    }

    func testDetectsNewerReleaseUsingNumericComparison() {
        XCTAssertTrue(UpdateChecker.isVersion("v0.1.10", newerThan: "0.1.2"))
        XCTAssertFalse(UpdateChecker.isVersion("v0.1.2", newerThan: "0.1.10"))
        XCTAssertFalse(UpdateChecker.isVersion("v0.1.2", newerThan: "0.1.2"))
    }

    func testRejectsWhitespaceOnlyReleaseTag() {
        XCTAssertEqual(UpdateChecker.normalizedVersion("   \n\t"), "")
    }
}
