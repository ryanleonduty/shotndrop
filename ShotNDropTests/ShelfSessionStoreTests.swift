import XCTest
@testable import ShotNDrop

final class ShelfSessionStoreTests: XCTestCase {
    private var scratch: URL!

    override func setUpWithError() throws {
        scratch = URL(fileURLWithPath: NSTemporaryDirectory(), isDirectory: true)
            .appendingPathComponent("shelf-store-tests-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: scratch, withIntermediateDirectories: true)
    }

    override func tearDownWithError() throws {
        try? FileManager.default.removeItem(at: scratch)
    }

    func testWriteCopiesBytes() throws {
        let store = try ShelfSessionStore(parentDirectory: scratch)
        let id = UUID()
        let url = try store.write(bytes: Data("payload".utf8), id: id, preferredExtension: "png")
        XCTAssertEqual(try Data(contentsOf: url), Data("payload".utf8))
        store.shutdown()
    }

    func testRemoveDeletesFile() throws {
        let store = try ShelfSessionStore(parentDirectory: scratch)
        let id = UUID()
        _ = try store.write(bytes: Data("x".utf8), id: id, preferredExtension: "png")
        store.remove(id: id)
        let entries = try FileManager.default.contentsOfDirectory(
            at: store.sessionDirectory,
            includingPropertiesForKeys: nil
        )
        XCTAssertFalse(entries.contains(where: { $0.lastPathComponent.hasPrefix(id.uuidString) }))
        store.shutdown()
    }

    func testShutdownRemovesDirectory() throws {
        let store = try ShelfSessionStore(parentDirectory: scratch)
        let dir = store.sessionDirectory
        store.shutdown()
        XCTAssertFalse(FileManager.default.fileExists(atPath: dir.path))
    }

    func testSweepRemovesUnlockedSibling() throws {
        // Create an orphan sibling (a directory with a .lock file we don't hold).
        let orphanName = "\(ShelfSessionStore.directoryPrefix)\(UUID().uuidString)"
        let orphanDir = scratch.appendingPathComponent(orphanName)
        try FileManager.default.createDirectory(at: orphanDir, withIntermediateDirectories: true)
        try Data().write(to: orphanDir.appendingPathComponent(ShelfSessionStore.lockFileName))

        let store = try ShelfSessionStore(parentDirectory: scratch)
        XCTAssertFalse(FileManager.default.fileExists(atPath: orphanDir.path),
                       "Sweep must remove sibling whose flock is not held")
        store.shutdown()
    }

    func testSweepLeavesLockedSiblingAlone() throws {
        let live = try ShelfSessionStore(parentDirectory: scratch)
        let liveDir = live.sessionDirectory

        // A second store in the same parent should NOT wipe the first.
        let second = try ShelfSessionStore(parentDirectory: scratch)
        XCTAssertTrue(FileManager.default.fileExists(atPath: liveDir.path),
                      "Sweep must leave a sibling whose flock is currently held")
        second.shutdown()
        live.shutdown()
    }
}
