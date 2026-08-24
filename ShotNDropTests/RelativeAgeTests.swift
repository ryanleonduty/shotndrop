import XCTest
@testable import ShotNDrop

final class RelativeAgeTests: XCTestCase {
    func testJustNow() {
        XCTAssertEqual(RelativeAge.format(interval: 0), "just now")
        XCTAssertEqual(RelativeAge.format(interval: 59), "just now")
    }

    func testMinutes() {
        XCTAssertEqual(RelativeAge.format(interval: 60), "1m ago")
        XCTAssertEqual(RelativeAge.format(interval: 59 * 60 + 30), "59m ago")
    }

    func testHours() {
        XCTAssertEqual(RelativeAge.format(interval: 60 * 60), "1h ago")
        XCTAssertEqual(RelativeAge.format(interval: 23 * 60 * 60), "23h ago")
    }

    func testCapsAtDay() {
        XCTAssertEqual(RelativeAge.format(interval: 24 * 60 * 60), "24h+ ago")
        XCTAssertEqual(RelativeAge.format(interval: 72 * 60 * 60), "24h+ ago")
    }
}
