import XCTest
import AppKit
@testable import ShotNDrop

final class ShelfMediaValidatorTests: XCTestCase {
    func testCanAcceptRejectsEmptyPasteboard() {
        let pb = NSPasteboard(name: NSPasteboard.Name(rawValue: "shelf.validator.empty"))
        pb.clearContents()
        let validator = ShelfMediaValidator()
        XCTAssertFalse(validator.canAccept(pasteboard: pb))
    }

    func testCanAcceptAcceptsImageFileURL() throws {
        let url = try Self.writeTempFile(name: "sample.png", bytes: Data(repeating: 0x89, count: 8))
        defer { try? FileManager.default.removeItem(at: url) }
        let pb = NSPasteboard(name: NSPasteboard.Name(rawValue: "shelf.validator.png"))
        pb.clearContents()
        pb.writeObjects([url as NSURL])
        let validator = ShelfMediaValidator()
        XCTAssertTrue(validator.canAccept(pasteboard: pb))
    }

    func testCanAcceptRejectsTextFileURL() throws {
        let url = try Self.writeTempFile(name: "sample.txt", bytes: Data("hello".utf8))
        defer { try? FileManager.default.removeItem(at: url) }
        let pb = NSPasteboard(name: NSPasteboard.Name(rawValue: "shelf.validator.txt"))
        pb.clearContents()
        pb.writeObjects([url as NSURL])
        let validator = ShelfMediaValidator()
        XCTAssertFalse(validator.canAccept(pasteboard: pb))
    }

    func testFinalizeRejectsEmptySnapshot() {
        let validator = ShelfMediaValidator()
        XCTAssertThrowsError(try validator.finalize(
            snapshot: Data(),
            originalFilename: "empty.png",
            capturedAt: Date(),
            sessionStoreURL: URL(fileURLWithPath: "/tmp/empty.png"),
            utiIdentifier: "public.png"
        ))
    }

    func testFingerprintDifferentForByteShiftedInput() throws {
        let a = Data(repeating: 0x11, count: 32 * 1024)
        var b = a
        b[0] = 0x22
        let fpA = ShelfMediaPayload.Fingerprint.compute(from: a)
        let fpB = ShelfMediaPayload.Fingerprint.compute(from: b)
        XCTAssertNotEqual(fpA.firstChunkHash, fpB.firstChunkHash)
    }

    static func writeTempFile(name: String, bytes: Data) throws -> URL {
        let dir = URL(fileURLWithPath: NSTemporaryDirectory(), isDirectory: true)
            .appendingPathComponent("shelf-validator-tests-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        let url = dir.appendingPathComponent(name)
        try bytes.write(to: url)
        return url
    }
}
