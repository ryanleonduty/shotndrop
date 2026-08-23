import SwiftUI
import AppKit
import ImageIO

public struct OverlayContentView: View {
    public let items: [ScreenshotItem]
    public let onCopy: (ScreenshotItem) -> Void
    public let onClose: (ScreenshotItem) -> Void
    public let onHoverChange: (Bool) -> Void

    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    public init(
        items: [ScreenshotItem],
        onCopy: @escaping (ScreenshotItem) -> Void,
        onClose: @escaping (ScreenshotItem) -> Void,
        onHoverChange: @escaping (Bool) -> Void = { _ in }
    ) {
        self.items = items
        self.onCopy = onCopy
        self.onClose = onClose
        self.onHoverChange = onHoverChange
    }

    public var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            ForEach(items) { item in
                thumbnailRow(for: item)
            }
        }
        .padding(12)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topTrailing)
        .animation(reduceMotion ? nil : .easeOut(duration: 0.15), value: items.map(\.id))
        .onHover(perform: onHoverChange)
    }

    @ViewBuilder
    private func thumbnailRow(for item: ScreenshotItem) -> some View {
        HStack(alignment: .center, spacing: 10) {
            FileDragView(url: item.url) {
                Thumbnail(url: item.url)
                    .frame(width: 64, height: 48)
                    .clipShape(RoundedRectangle(cornerRadius: 6, style: .continuous))
                    .overlay(
                        RoundedRectangle(cornerRadius: 6, style: .continuous)
                            .stroke(Color.primary.opacity(0.1))
                    )
            }
            .accessibilityLabel(Text("Drag \(item.url.lastPathComponent)"))

            VStack(alignment: .leading, spacing: 2) {
                Text(item.url.lastPathComponent)
                    .font(.caption)
                    .lineLimit(1)
                Text(item.creationDate.formatted(date: .omitted, time: .shortened))
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }
            Spacer(minLength: 4)
            Button {
                onCopy(item)
            } label: {
                Image(systemName: "doc.on.doc")
            }
            .buttonStyle(.borderless)
            .accessibilityLabel(Text("Copy \(item.url.lastPathComponent)"))

            Button {
                onClose(item)
            } label: {
                Image(systemName: "xmark")
            }
            .buttonStyle(.borderless)
            .accessibilityLabel(Text("Close \(item.url.lastPathComponent)"))
        }
    }
}

private struct Thumbnail: View {
    let url: URL

    var body: some View {
        if let image = ThumbnailCache.shared.thumbnail(for: url) {
            Image(nsImage: image)
                .resizable()
                .scaledToFill()
        } else {
            Color.gray.opacity(0.3)
        }
    }
}

/// Bounded thumbnail cache. Downsamples to a display-sized ceiling and caps
/// total cost at 64 MiB. Cleared on quit via `purge()`.
public final class ThumbnailCache: @unchecked Sendable {
    public static let shared = ThumbnailCache()
    private static let costLimit: Int = 64 * 1024 * 1024
    private static let maxPixelDimension: CGFloat = 256

    private let cache: NSCache<NSURL, NSImage>

    private init() {
        cache = NSCache()
        cache.totalCostLimit = Self.costLimit
        cache.countLimit = 128
    }

    public func thumbnail(for url: URL) -> NSImage? {
        let key = url as NSURL
        if let existing = cache.object(forKey: key) {
            return existing
        }
        guard let downsampled = Self.downsample(url: url, maxPixelDimension: Self.maxPixelDimension) else {
            return nil
        }
        let width = Int(downsampled.size.width)
        let height = Int(downsampled.size.height)
        let cost = width * height * 4
        cache.setObject(downsampled, forKey: key, cost: cost)
        return downsampled
    }

    public func purge() {
        cache.removeAllObjects()
    }

    private static func downsample(url: URL, maxPixelDimension: CGFloat) -> NSImage? {
        let sourceOptions: [CFString: Any] = [
            kCGImageSourceShouldCache: false
        ]
        guard let source = CGImageSourceCreateWithURL(url as CFURL, sourceOptions as CFDictionary) else {
            return nil
        }
        let options: [CFString: Any] = [
            kCGImageSourceCreateThumbnailFromImageAlways: true,
            kCGImageSourceThumbnailMaxPixelSize: maxPixelDimension,
            kCGImageSourceCreateThumbnailWithTransform: true,
            kCGImageSourceShouldCacheImmediately: false
        ]
        guard let cg = CGImageSourceCreateThumbnailAtIndex(source, 0, options as CFDictionary) else {
            return nil
        }
        return NSImage(cgImage: cg, size: NSSize(width: cg.width, height: cg.height))
    }
}
