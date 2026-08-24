import Foundation
import AppKit
import ImageIO

/// Small `NSCache`-backed thumbnailer keyed by `ShelfMediaPayload.id`. The
/// cache count limit is set to double the inventory cap for headroom.
public final class ShelfThumbnailer: @unchecked Sendable {
    public static let shared = ShelfThumbnailer()

    private let cache = NSCache<NSString, NSImage>()
    private let maxPixelSize: Int

    public init(maxPixelSize: Int = 112, countLimit: Int = 40) {
        self.maxPixelSize = maxPixelSize
        cache.countLimit = countLimit
    }

    public func thumbnail(for payload: ShelfMediaPayload) -> NSImage? {
        let key = payload.id.uuidString as NSString
        if let cached = cache.object(forKey: key) {
            return cached
        }
        guard let cg = makeThumbnail(url: payload.sessionStoreURL) else { return nil }
        let image = NSImage(cgImage: cg, size: NSSize(width: cg.width, height: cg.height))
        cache.setObject(image, forKey: key)
        return image
    }

    public func invalidate(id: UUID) {
        cache.removeObject(forKey: id.uuidString as NSString)
    }

    public func purgeAll() {
        cache.removeAllObjects()
    }

    private func makeThumbnail(url: URL) -> CGImage? {
        guard let source = CGImageSourceCreateWithURL(url as CFURL, nil) else { return nil }
        let options: [CFString: Any] = [
            kCGImageSourceCreateThumbnailFromImageAlways: true,
            kCGImageSourceThumbnailMaxPixelSize: maxPixelSize,
            kCGImageSourceCreateThumbnailWithTransform: true
        ]
        return CGImageSourceCreateThumbnailAtIndex(source, 0, options as CFDictionary)
    }
}
