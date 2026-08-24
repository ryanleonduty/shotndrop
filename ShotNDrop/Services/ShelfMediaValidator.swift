import Foundation
import AppKit
import ImageIO
import UniformTypeIdentifiers

/// Two-phase drop validator:
/// * `canAccept(dragInfo:)` is a synchronous metadata-only check consulted
///   from `NSDraggingDestination.draggingEntered:`. It reads only the drag
///   pasteboard's file-URL UTI and rejects everything not in the accepted
///   image set. It must not read file bytes.
/// * `finalize(snapshot:...)` is called on the async copy path after
///   `performDragOperation:` has snapshotted the bytes. It inspects the
///   snapshot for well-formedness, extracts dimensions, computes the
///   duplicate fingerprint, and produces the immutable `ShelfMediaPayload`.
public struct ShelfMediaValidator: Sendable {
    public enum FinalizeError: Error, Equatable, Sendable {
        case emptySnapshot
        case unreadableImage
    }

    public static let acceptedUTIs: Set<String> = [
        "public.png",
        "public.jpeg",
        "public.heic",
        "public.tiff",
        "org.webmproject.webp",
        "com.compuserve.gif"
    ]

    public init() {}

    /// Returns true when the drag pasteboard advertises at least one file URL
    /// whose UTI is in the accepted set. No file bytes are read.
    @MainActor
    public func canAccept(dragInfo: NSDraggingInfo) -> Bool {
        canAccept(pasteboard: dragInfo.draggingPasteboard)
    }

    public func canAccept(pasteboard: NSPasteboard) -> Bool {
        // 1) File URL path — an image-typed file on disk.
        if pasteboardHasAcceptedFileURL(pasteboard) { return true }

        // 2) Raw image bytes — macOS screenshot thumbnail often puts a TIFF
        //    or PNG directly on the pasteboard even without a file URL.
        let rawImageTypes: [NSPasteboard.PasteboardType] = [
            .tiff, .png,
            NSPasteboard.PasteboardType("public.image"),
            NSPasteboard.PasteboardType("public.jpeg"),
            NSPasteboard.PasteboardType("public.heic"),
            NSPasteboard.PasteboardType("com.compuserve.gif")
        ]
        for type in rawImageTypes {
            if pasteboard.data(forType: type) != nil { return true }
        }

        // 3) File promise — the source will hand over a file later; accept
        //    and let performDragOperation resolve it.
        let promiseTypes: [NSPasteboard.PasteboardType] = [
            NSPasteboard.PasteboardType("com.apple.pasteboard.promised-file-content-type"),
            NSPasteboard.PasteboardType("com.apple.pasteboard.promised-file-url"),
            NSPasteboard.PasteboardType("com.apple.NSFilePromiseReceiver")
        ]
        let advertised = pasteboard.types ?? []
        for type in promiseTypes where advertised.contains(type) {
            return true
        }
        return false
    }

    private func pasteboardHasAcceptedFileURL(_ pasteboard: NSPasteboard) -> Bool {
        if let items = pasteboard.pasteboardItems {
            for item in items {
                if firstAcceptedUTI(on: item) != nil { return true }
            }
        }
        let types = pasteboard.types ?? []
        if types.contains(.fileURL) {
            if let urls = pasteboard.readObjects(forClasses: [NSURL.self], options: nil) as? [URL] {
                return urls.contains(where: { isAcceptedURL($0) })
            }
        }
        return false
    }

    private func firstAcceptedUTI(on item: NSPasteboardItem) -> String? {
        for utiType in item.types {
            let raw = utiType.rawValue
            if Self.acceptedUTIs.contains(raw) { return raw }
            // Occasionally the pasteboard advertises a conformant type (e.g.
            // `dyn.*`); resolve through UTType conformance for accepted image
            // types.
            if let type = UTType(raw), acceptedUTTypes.contains(where: { type.conforms(to: $0) }) {
                return raw
            }
        }
        // Some sources advertise a file URL string only.
        if let urlString = item.string(forType: .fileURL),
           let url = URL(string: urlString), isAcceptedURL(url) {
            return url.pathExtension
        }
        return nil
    }

    private var acceptedUTTypes: [UTType] {
        [.png, .jpeg, .heic, .tiff, .webP, .gif].compactMap { $0 }
    }

    private func isAcceptedURL(_ url: URL) -> Bool {
        let ext = url.pathExtension.lowercased()
        let extMap: [String: String] = [
            "png": "public.png",
            "jpg": "public.jpeg",
            "jpeg": "public.jpeg",
            "heic": "public.heic",
            "tif": "public.tiff",
            "tiff": "public.tiff",
            "webp": "org.webmproject.webp",
            "gif": "com.compuserve.gif"
        ]
        return extMap[ext] != nil
    }

    /// Inspects a synchronously captured drop snapshot and produces a
    /// finalized payload. Duplicate detection against `previousFingerprints`
    /// happens on the caller side after this returns.
    public func finalize(
        snapshot: Data,
        originalFilename: String,
        capturedAt: Date,
        sessionStoreURL: URL,
        utiIdentifier: String,
        id: UUID = UUID()
    ) throws -> ShelfMediaPayload {
        guard !snapshot.isEmpty else { throw FinalizeError.emptySnapshot }

        let dimensions = Self.readDimensions(from: snapshot)
        let fingerprint = ShelfMediaPayload.Fingerprint.compute(from: snapshot)

        return ShelfMediaPayload(
            id: id,
            kind: .image,
            sessionStoreURL: sessionStoreURL,
            originalFilename: originalFilename,
            capturedAt: capturedAt,
            sizeBytes: snapshot.count,
            dimensions: dimensions,
            fingerprint: fingerprint,
            utiIdentifier: utiIdentifier
        )
    }

    private static func readDimensions(from bytes: Data) -> ShelfMediaPayload.Dimensions? {
        let options: [CFString: Any] = [kCGImageSourceShouldCache: false]
        guard let source = CGImageSourceCreateWithData(bytes as CFData, options as CFDictionary),
              CGImageSourceGetCount(source) > 0,
              let props = CGImageSourceCopyPropertiesAtIndex(source, 0, options as CFDictionary) as? [CFString: Any],
              let width = props[kCGImagePropertyPixelWidth] as? Int,
              let height = props[kCGImagePropertyPixelHeight] as? Int else {
            return nil
        }
        return ShelfMediaPayload.Dimensions(width: width, height: height)
    }
}
