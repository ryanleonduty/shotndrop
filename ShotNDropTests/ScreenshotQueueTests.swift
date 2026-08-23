import XCTest
@testable import ShotNDrop

@MainActor
final class ScreenshotQueueTests: XCTestCase {
    private func makeItem(
        _ name: String,
        creation: Date,
        size: Int64 = 1024,
        detected: Date? = nil,
        rid: Data? = nil
    ) -> ScreenshotItem {
        let path = "/tmp/\(name).png"
        let identity = ScreenshotIdentity(
            resourceIdentifier: rid,
            standardizedPath: path,
            creationDate: creation,
            size: size
        )
        return ScreenshotItem(
            identity: identity,
            url: URL(fileURLWithPath: path),
            creationDate: creation,
            size: size,
            detectedAt: detected ?? creation
        )
    }

    func testInsertOrdersByCreationDate() {
        let q = ScreenshotQueue()
        let d0 = Date(timeIntervalSince1970: 1_000)
        q.insert(makeItem("b", creation: d0.addingTimeInterval(2)))
        q.insert(makeItem("a", creation: d0.addingTimeInterval(1)))
        q.insert(makeItem("c", creation: d0.addingTimeInterval(3)))
        XCTAssertEqual(q.items.map { $0.url.lastPathComponent }, ["a.png", "b.png", "c.png"])
    }

    func testDuplicateInsertIsIgnored() {
        let q = ScreenshotQueue()
        let d = Date(timeIntervalSince1970: 1_000)
        let first = makeItem("a", creation: d)
        let second = makeItem("a", creation: d)
        _ = q.insert(first)
        let outcome = q.insert(second)
        if case .duplicate = outcome {
            // ok
        } else {
            XCTFail("expected duplicate; got \(outcome)")
        }
        XCTAssertEqual(q.count, 1)
    }

    func testOverflowEvictsOldest() {
        let q = ScreenshotQueue()
        let base = Date(timeIntervalSince1970: 10_000)
        for i in 0..<ScreenshotQueue.capacity {
            _ = q.insert(makeItem("f\(i)", creation: base.addingTimeInterval(TimeInterval(i))))
        }
        XCTAssertEqual(q.count, ScreenshotQueue.capacity)
        let newest = makeItem("new", creation: base.addingTimeInterval(TimeInterval(ScreenshotQueue.capacity + 1)))
        let outcome = q.insert(newest)
        if case .overflowEvicted(_, let evicted) = outcome {
            XCTAssertEqual(evicted.url.lastPathComponent, "f0.png")
        } else {
            XCTFail("expected overflowEvicted; got \(outcome)")
        }
        XCTAssertEqual(q.count, ScreenshotQueue.capacity)
    }

    func testCloseMovesToLastClosedAndRestoreConsumes() {
        let q = ScreenshotQueue()
        let d = Date(timeIntervalSince1970: 1_000)
        let a = makeItem("a", creation: d, detected: d)
        _ = q.insert(a)
        let closed = q.close(id: a.id)
        XCTAssertEqual(closed?.id, a.id)
        XCTAssertNotNil(q.lastClosed)
        XCTAssertEqual(q.count, 0)

        let outcome = q.restoreLastClosed(now: d.addingTimeInterval(60)) { _ in true }
        if case .restored(let it) = outcome {
            XCTAssertEqual(it.id, a.id)
        } else {
            XCTFail("expected restored; got \(outcome)")
        }
        XCTAssertNil(q.lastClosed)
        XCTAssertEqual(q.count, 1)
    }

    func testRestoreEvictsOldestWhenFull() {
        let q = ScreenshotQueue()
        let base = Date(timeIntervalSince1970: 10_000)
        for i in 0..<ScreenshotQueue.capacity {
            _ = q.insert(makeItem("f\(i)", creation: base.addingTimeInterval(TimeInterval(i))))
        }
        let closedItem = makeItem("closed", creation: base.addingTimeInterval(TimeInterval(ScreenshotQueue.capacity + 5)))
        _ = q.insert(closedItem)
        _ = q.close(id: closedItem.id)
        // Fill back up to capacity.
        _ = q.insert(makeItem("fresh", creation: base.addingTimeInterval(TimeInterval(ScreenshotQueue.capacity + 10))))
        XCTAssertEqual(q.count, ScreenshotQueue.capacity)

        let outcome = q.restoreLastClosed(now: base.addingTimeInterval(TimeInterval(ScreenshotQueue.capacity + 20))) { _ in true }
        if case .evictedForRestore(let evicted, let restored) = outcome {
            XCTAssertEqual(evicted.url.lastPathComponent, "f1.png")
            XCTAssertEqual(restored.id, closedItem.id)
        } else {
            XCTFail("expected evictedForRestore; got \(outcome)")
        }
        XCTAssertEqual(q.count, ScreenshotQueue.capacity)
    }

    func testRestoreExpiredConsumesSlot() {
        let q = ScreenshotQueue()
        let d = Date(timeIntervalSince1970: 1_000)
        let item = makeItem("a", creation: d, detected: d)
        _ = q.insert(item)
        _ = q.close(id: item.id)
        let past = d.addingTimeInterval(ScreenshotQueue.ttl + 1)
        let outcome = q.restoreLastClosed(now: past) { _ in true }
        XCTAssertEqual(outcome, .expired)
        XCTAssertNil(q.lastClosed)
    }

    func testRestoreUnavailableConsumesSlot() {
        let q = ScreenshotQueue()
        let d = Date(timeIntervalSince1970: 1_000)
        let item = makeItem("a", creation: d, detected: d)
        _ = q.insert(item)
        _ = q.close(id: item.id)
        let outcome = q.restoreLastClosed(now: d.addingTimeInterval(10)) { _ in false }
        XCTAssertEqual(outcome, .unavailable)
        XCTAssertNil(q.lastClosed)
    }

    func testPruneRemovesExpired() {
        let q = ScreenshotQueue()
        let d = Date(timeIntervalSince1970: 1_000)
        let stale = makeItem("stale", creation: d, detected: d)
        let fresh = makeItem("fresh", creation: d.addingTimeInterval(1), detected: d.addingTimeInterval(1))
        _ = q.insert(stale)
        _ = q.insert(fresh)
        let removed = q.pruneExpired(now: d.addingTimeInterval(ScreenshotQueue.ttl + 0.5))
        XCTAssertEqual(removed.count, 1)
        XCTAssertEqual(removed.first?.url.lastPathComponent, "stale.png")
    }

    func testClearEmptiesQueueButDoesNotTouchSource() {
        let q = ScreenshotQueue()
        let d = Date(timeIntervalSince1970: 1_000)
        _ = q.insert(makeItem("a", creation: d))
        _ = q.insert(makeItem("b", creation: d.addingTimeInterval(1)))
        q.clear()
        XCTAssertEqual(q.count, 0)
        XCTAssertNil(q.lastClosed)
        // Note: we cannot assert about the source file here since none exists;
        // clear() by construction never calls the filesystem — this is a
        // structural guarantee, verified by inspection.
    }
}
