import XCTest
@testable import ShotNDrop

@MainActor
final class ShelfInventoryTests: XCTestCase {
    func testCapacityRejectsBeyondTwenty() throws {
        let inventory = ShelfInventory()
        for _ in 0..<20 {
            XCTAssertNotNil(inventory.reservePending())
        }
        XCTAssertEqual(inventory.count, 20)
        XCTAssertNil(inventory.reservePending(), "21st reservation must be rejected")
    }

    func testResolveTransitionsPendingToReady() throws {
        let inventory = ShelfInventory()
        guard let id = inventory.reservePending() else { return XCTFail("reserve failed") }
        let payload = Self.makePayload(id: id)
        XCTAssertTrue(inventory.resolve(id: id, with: payload))
        XCTAssertEqual(inventory.readyPayloads.count, 1)
        XCTAssertEqual(inventory.readyPayloads.first?.id, id)
    }

    func testFailRemovesPendingSlot() throws {
        let inventory = ShelfInventory()
        guard let id = inventory.reservePending() else { return XCTFail() }
        XCTAssertEqual(inventory.count, 1)
        XCTAssertTrue(inventory.fail(id: id, reason: .duplicate))
        XCTAssertEqual(inventory.count, 0)
    }

    func testDuplicateFingerprintDetected() throws {
        let inventory = ShelfInventory()
        let id = inventory.reservePending()!
        let payload = Self.makePayload(id: id)
        _ = inventory.resolve(id: id, with: payload)
        XCTAssertTrue(inventory.containsDuplicate(fingerprint: payload.fingerprint))
    }

    func testRemoveById() throws {
        let inventory = ShelfInventory()
        let id = inventory.reservePending()!
        _ = inventory.resolve(id: id, with: Self.makePayload(id: id))
        XCTAssertNotNil(inventory.remove(id: id))
        XCTAssertTrue(inventory.isEmpty)
    }

    func testClearEmpties() throws {
        let inventory = ShelfInventory()
        _ = inventory.reservePending()
        _ = inventory.reservePending()
        inventory.clear()
        XCTAssertTrue(inventory.isEmpty)
    }

    func testNewestFirstOrdering() throws {
        let inventory = ShelfInventory()
        let first = inventory.reservePending()!
        let second = inventory.reservePending()!
        XCTAssertEqual(inventory.slots.first?.id, second)
        XCTAssertEqual(inventory.slots.last?.id, first)
    }

    // MARK: helpers

    static func makePayload(id: UUID) -> ShelfMediaPayload {
        let data = Data(repeating: 0xAB, count: 128)
        return ShelfMediaPayload(
            id: id,
            kind: .image,
            sessionStoreURL: URL(fileURLWithPath: "/tmp/\(id.uuidString).png"),
            originalFilename: "\(id.uuidString).png",
            capturedAt: Date(),
            sizeBytes: data.count,
            dimensions: ShelfMediaPayload.Dimensions(width: 100, height: 100),
            fingerprint: ShelfMediaPayload.Fingerprint.compute(from: data),
            utiIdentifier: "public.png"
        )
    }
}
