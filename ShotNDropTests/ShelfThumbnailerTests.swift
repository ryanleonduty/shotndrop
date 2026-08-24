import XCTest
import AppKit
import CoreGraphics
@testable import ShotNDrop

final class ShelfThumbnailerTests: XCTestCase {
    private var scratch: URL!

    override func setUpWithError() throws {
        scratch = URL(fileURLWithPath: NSTemporaryDirectory(), isDirectory: true)
            .appendingPathComponent("thumb-tests-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: scratch, withIntermediateDirectories: true)
    }

    override func tearDownWithError() throws {
        try? FileManager.default.removeItem(at: scratch)
    }

    func testMissingFileReturnsNil() {
        let thumbnailer = ShelfThumbnailer(maxPixelSize: 112, countLimit: 8)
        let bogus = ShelfMediaPayload(
            id: UUID(),
            kind: .image,
            sessionStoreURL: scratch.appendingPathComponent("does-not-exist.png"),
            originalFilename: "x.png",
            capturedAt: Date(),
            sizeBytes: 0,
            dimensions: nil,
            fingerprint: ShelfMediaPayload.Fingerprint(byteCount: 0, firstChunkHash: Data(), lastChunkHash: Data()),
            utiIdentifier: "public.png"
        )
        XCTAssertNil(thumbnailer.thumbnail(for: bogus))
    }

    func testGeneratesAndCachesThumbnail() throws {
        // Emit a small PNG.
        let url = scratch.appendingPathComponent("sample.png")
        try Self.writeSolidPNG(to: url, width: 128, height: 128)

        let payload = ShelfMediaPayload(
            id: UUID(),
            kind: .image,
            sessionStoreURL: url,
            originalFilename: "sample.png",
            capturedAt: Date(),
            sizeBytes: (try? Data(contentsOf: url).count) ?? 0,
            dimensions: ShelfMediaPayload.Dimensions(width: 128, height: 128),
            fingerprint: ShelfMediaPayload.Fingerprint(byteCount: 0, firstChunkHash: Data(), lastChunkHash: Data()),
            utiIdentifier: "public.png"
        )

        let thumbnailer = ShelfThumbnailer(maxPixelSize: 64, countLimit: 4)
        guard let image = thumbnailer.thumbnail(for: payload) else {
            return XCTFail("Expected thumbnail")
        }
        XCTAssertLessThanOrEqual(max(image.size.width, image.size.height), 64)
        // Second call is a cache hit — must return same instance identity.
        XCTAssertTrue(thumbnailer.thumbnail(for: payload) === image)
        thumbnailer.invalidate(id: payload.id)
        XCTAssertFalse(thumbnailer.thumbnail(for: payload) === image)
    }

    // MARK: helper

    private static func writeSolidPNG(to url: URL, width: Int, height: Int) throws {
        let bitsPerComponent = 8
        let bytesPerRow = width * 4
        let colorSpace = CGColorSpaceCreateDeviceRGB()
        let context = CGContext(data: nil, width: width, height: height,
                                bitsPerComponent: bitsPerComponent, bytesPerRow: bytesPerRow,
                                space: colorSpace,
                                bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
        context.setFillColor(CGColor(red: 1, green: 0, blue: 0, alpha: 1))
        context.fill(CGRect(x: 0, y: 0, width: width, height: height))
        guard let cg = context.makeImage() else { throw NSError(domain: "test", code: 0) }
        let rep = NSBitmapImageRep(cgImage: cg)
        guard let data = rep.representation(using: .png, properties: [:]) else {
            throw NSError(domain: "test", code: 1)
        }
        try data.write(to: url)
    }
}
