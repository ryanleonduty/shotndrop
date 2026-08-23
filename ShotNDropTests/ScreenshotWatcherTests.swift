import XCTest
import UniformTypeIdentifiers
@testable import ShotNDrop

private struct FixedProbe: ImageReadinessProbe {
    let completeURLs: Set<String>
    func isComplete(_ url: URL) -> Bool {
        completeURLs.contains(url.standardizedFileURL.path)
    }
}

final class ScreenshotWatcherTests: XCTestCase {
    private func makeEntry(
        _ name: String,
        creation: Date,
        modification: Date? = nil,
        size: Int64 = 4096,
        contentType: UTType = .png,
        isRegularFile: Bool = true
    ) -> FolderEntry {
        let url = URL(fileURLWithPath: "/tmp/watch/\(name)")
        let mod = modification ?? creation
        return FolderEntry(
            url: url,
            standardizedPath: url.standardizedFileURL.path,
            creationDate: creation,
            modificationDate: mod,
            size: size,
            resourceIdentifier: name.data(using: .utf8),
            isRegularFile: isRegularFile,
            contentType: contentType
        )
    }

    func testPreCutoverEntriesDoNotEnterQueue() {
        let cutover = Date(timeIntervalSince1970: 10_000)
        var engine = WatcherEngine(baselineStartedAt: cutover)
        let older = makeEntry("old.png", creation: cutover.addingTimeInterval(-10))
        let probe = FixedProbe(completeURLs: [older.standardizedPath])
        let decision = engine.reconcile(
            snapshot: [older],
            now: cutover,
            probe: probe
        )
        XCTAssertTrue(decision.accepted.isEmpty)
        XCTAssertEqual(decision.pendingCount, 0)
    }

    func testBaselineScanRaceAcceptsFileBornDuringSeam() {
        // A file whose creationDate is >= cutover must still be accepted even
        // if it appeared during the baseline scan.
        let cutover = Date(timeIntervalSince1970: 10_000)
        var engine = WatcherEngine(baselineStartedAt: cutover)
        let e = makeEntry("race.png", creation: cutover.addingTimeInterval(0.01))
        let probe = FixedProbe(completeURLs: [e.standardizedPath])
        // First reconcile enters pending; needs another reconcile after
        // >=quietWindow with stable metadata to be accepted.
        var now = cutover.addingTimeInterval(0.02)
        var decision = engine.reconcile(snapshot: [e], now: now, probe: probe)
        XCTAssertEqual(decision.pendingCount, 1)
        XCTAssertTrue(decision.accepted.isEmpty)

        now = now.addingTimeInterval(WatcherEngine.quietWindow + 0.01)
        decision = engine.reconcile(snapshot: [e], now: now, probe: probe)
        XCTAssertEqual(decision.accepted.count, 1)
        XCTAssertEqual(decision.accepted.first?.url.lastPathComponent, "race.png")
    }

    func testCoalescedEventsProduceOneItem() {
        let cutover = Date(timeIntervalSince1970: 1_000)
        var engine = WatcherEngine(baselineStartedAt: cutover)
        let e = makeEntry("one.png", creation: cutover.addingTimeInterval(1))
        let probe = FixedProbe(completeURLs: [e.standardizedPath])
        var now = cutover.addingTimeInterval(1)
        _ = engine.reconcile(snapshot: [e], now: now, probe: probe)
        now = now.addingTimeInterval(WatcherEngine.quietWindow + 0.01)
        let first = engine.reconcile(snapshot: [e], now: now, probe: probe)
        XCTAssertEqual(first.accepted.count, 1)
        // Repeated events with the same identity should produce nothing more.
        now = now.addingTimeInterval(1)
        let second = engine.reconcile(snapshot: [e], now: now, probe: probe)
        XCTAssertTrue(second.accepted.isEmpty)
    }

    func testDecodablePrefixPausedResetsQuietWindow() {
        let cutover = Date(timeIntervalSince1970: 1_000)
        var engine = WatcherEngine(baselineStartedAt: cutover)
        var e = makeEntry("prefix.png", creation: cutover.addingTimeInterval(1), size: 1024)
        var probe = FixedProbe(completeURLs: [e.standardizedPath])
        var now = cutover.addingTimeInterval(1)
        // Enter pending.
        _ = engine.reconcile(snapshot: [e], now: now, probe: probe)
        // Advance past the quiet window but then metadata changes (final write).
        now = now.addingTimeInterval(WatcherEngine.quietWindow + 0.01)
        e = FolderEntry(
            url: e.url,
            standardizedPath: e.standardizedPath,
            creationDate: e.creationDate,
            modificationDate: e.modificationDate.addingTimeInterval(0.5),
            size: 2048,
            resourceIdentifier: e.resourceIdentifier,
            isRegularFile: true,
            contentType: .png
        )
        // Metadata changed — engine must reset the stability anchor, not accept.
        let intermediate = engine.reconcile(snapshot: [e], now: now, probe: probe)
        XCTAssertTrue(intermediate.accepted.isEmpty)
        // Now hold metadata stable for a fresh quiet window.
        probe = FixedProbe(completeURLs: [e.standardizedPath])
        now = now.addingTimeInterval(WatcherEngine.quietWindow + 0.01)
        let accepted = engine.reconcile(snapshot: [e], now: now, probe: probe)
        XCTAssertEqual(accepted.accepted.count, 1)
    }

    func testIncompleteImageIsNotAccepted() {
        let cutover = Date(timeIntervalSince1970: 1_000)
        var engine = WatcherEngine(baselineStartedAt: cutover)
        let e = makeEntry("partial.png", creation: cutover.addingTimeInterval(1))
        let probe = FixedProbe(completeURLs: []) // never complete
        var now = cutover.addingTimeInterval(1)
        _ = engine.reconcile(snapshot: [e], now: now, probe: probe)
        now = now.addingTimeInterval(WatcherEngine.quietWindow + 1)
        let decision = engine.reconcile(snapshot: [e], now: now, probe: probe)
        XCTAssertTrue(decision.accepted.isEmpty)
        XCTAssertEqual(decision.pendingCount, 1)
    }

    func testDeletedFileRemovesPending() {
        let cutover = Date(timeIntervalSince1970: 1_000)
        var engine = WatcherEngine(baselineStartedAt: cutover)
        let e = makeEntry("bye.png", creation: cutover.addingTimeInterval(1))
        let probe = FixedProbe(completeURLs: [e.standardizedPath])
        _ = engine.reconcile(snapshot: [e], now: cutover.addingTimeInterval(1), probe: probe)
        let decision = engine.reconcile(snapshot: [], now: cutover.addingTimeInterval(2), probe: probe)
        XCTAssertEqual(decision.pendingCount, 0)
        XCTAssertTrue(decision.accepted.isEmpty)
    }

    func testBurstMaintainsCreationOrder() {
        let cutover = Date(timeIntervalSince1970: 1_000)
        var engine = WatcherEngine(baselineStartedAt: cutover)
        let a = makeEntry("a.png", creation: cutover.addingTimeInterval(1))
        let b = makeEntry("b.png", creation: cutover.addingTimeInterval(2))
        let c = makeEntry("c.png", creation: cutover.addingTimeInterval(3))
        let probe = FixedProbe(completeURLs: [a.standardizedPath, b.standardizedPath, c.standardizedPath])
        var now = cutover.addingTimeInterval(3)
        _ = engine.reconcile(snapshot: [b, a, c], now: now, probe: probe)
        now = now.addingTimeInterval(WatcherEngine.quietWindow + 0.01)
        let decision = engine.reconcile(snapshot: [b, a, c], now: now, probe: probe)
        XCTAssertEqual(decision.accepted.map(\.url.lastPathComponent), ["a.png", "b.png", "c.png"])
    }

    func testPendingCapCapsFanIn() {
        let cutover = Date(timeIntervalSince1970: 1_000)
        var engine = WatcherEngine(baselineStartedAt: cutover)
        let entries = (0..<(WatcherEngine.pendingCap + 8)).map { i in
            makeEntry("burst-\(i).png", creation: cutover.addingTimeInterval(TimeInterval(i + 1)))
        }
        let probe = FixedProbe(completeURLs: []) // keep everything pending
        let decision = engine.reconcile(snapshot: entries, now: cutover.addingTimeInterval(10), probe: probe)
        XCTAssertEqual(decision.pendingCount, WatcherEngine.pendingCap)
    }

    func testInvalidateClearsPending() {
        let cutover = Date(timeIntervalSince1970: 1_000)
        var engine = WatcherEngine(baselineStartedAt: cutover)
        let e = makeEntry("a.png", creation: cutover.addingTimeInterval(1))
        let probe = FixedProbe(completeURLs: [])
        _ = engine.reconcile(snapshot: [e], now: cutover.addingTimeInterval(1), probe: probe)
        engine.invalidate()
        let decision = engine.reconcile(snapshot: [], now: cutover.addingTimeInterval(2), probe: probe)
        XCTAssertEqual(decision.pendingCount, 0)
    }

    func testAcceptedIdentitiesSurviveInvalidation() {
        let cutover = Date(timeIntervalSince1970: 1_000)
        var engine = WatcherEngine(baselineStartedAt: cutover)
        let e = makeEntry("stay.png", creation: cutover.addingTimeInterval(1))
        let probe = FixedProbe(completeURLs: [e.standardizedPath])
        var now = cutover.addingTimeInterval(1)
        _ = engine.reconcile(snapshot: [e], now: now, probe: probe)
        now = now.addingTimeInterval(WatcherEngine.quietWindow + 0.01)
        let first = engine.reconcile(snapshot: [e], now: now, probe: probe)
        XCTAssertEqual(first.accepted.count, 1)
        engine.invalidate()
        now = now.addingTimeInterval(WatcherEngine.quietWindow + 0.01)
        let after = engine.reconcile(snapshot: [e], now: now, probe: probe)
        XCTAssertTrue(after.accepted.isEmpty)
    }
}
