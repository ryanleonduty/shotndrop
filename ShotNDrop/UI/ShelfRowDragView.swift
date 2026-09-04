import AppKit
import SwiftUI
import UniformTypeIdentifiers

/// AppKit drag source that starts a real
/// `beginDraggingSession(with:event:source:)` on mouseDown-plus-drag.
///
/// The app is sandboxed, so the session store lives inside the app's container
/// (`~/Library/Containers/<bundle id>/Data/tmp/…`). That path is unreadable by
/// other apps, so advertising only a file URL leaves a destination like Figma
/// unable to validate the drop — it withholds the copy cursor and often rejects
/// the drag. To hand image data across the sandbox boundary we put the bytes on
/// the pasteboard *eagerly* (see `beginDrag`); a destination consumes them
/// directly, independent of file-path readability. The file URL is still
/// advertised for file-oriented destinations (e.g. Finder) that can reach it.
final class ShelfRowDragView: NSView, NSDraggingSource {
    let payload: ShelfMediaPayload
    let onDragConsumed: () -> Void
    private var mouseDownPoint: NSPoint?

    init(payload: ShelfMediaPayload, onDragConsumed: @escaping () -> Void) {
        self.payload = payload
        self.onDragConsumed = onDragConsumed
        super.init(frame: .zero)
        wantsLayer = true
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError() }

    override func hitTest(_ point: NSPoint) -> NSView? {
        // Claim mouse events for the whole row so we can start a drag,
        // regardless of any SwiftUI child gestures.
        return self
    }

    override func mouseDown(with event: NSEvent) {
        mouseDownPoint = event.locationInWindow
        Self.trace("mouseDown row=\(payload.originalFilename)")
    }

    override func mouseDragged(with event: NSEvent) {
        guard let start = mouseDownPoint else { return }
        let current = event.locationInWindow
        let dx = current.x - start.x
        let dy = current.y - start.y
        if sqrt(dx * dx + dy * dy) < 4 { return }
        mouseDownPoint = nil
        Self.trace("mouseDragged→beginDrag row=\(payload.originalFilename) uti=\(payload.utiIdentifier)")
        beginDrag(with: event)
    }

    override func mouseUp(with event: NSEvent) {
        mouseDownPoint = nil
    }

    // MARK: NSDraggingSource

    func draggingSession(
        _ session: NSDraggingSession,
        sourceOperationMaskFor context: NSDraggingContext
    ) -> NSDragOperation {
        // Advertise `.copy` only — never `.move`/`.link`.
        return .copy
    }

    func draggingSession(
        _ session: NSDraggingSession,
        endedAt screenPoint: NSPoint,
        operation: NSDragOperation
    ) {
        Self.trace("draggingSession ended operation=\(operation.rawValue)")
        if operation == .copy {
            DispatchQueue.main.async { [onDragConsumed] in
                onDragConsumed()
            }
        } else if operation.rawValue != 0 && operation != .copy {
            Self.trace("drag-out ended with non-.copy operation=\(operation.rawValue) — destination violated advertised mask")
        }
    }

    // MARK: File-based diagnostic trace (survives log-stream filtering).

    private static let traceURL: URL = {
        // Must be inside the sandbox container — writes anywhere else are
        // silently denied by app-sandbox. The path is printed to stdout on
        // first init so the developer knows where to tail.
        let base = URL(fileURLWithPath: NSTemporaryDirectory(), isDirectory: true)
        let url = base.appendingPathComponent("shotndrop-drag.log")
        FileHandle.standardError.write(Data("[ShotNDrop trace] \(url.path)\n".utf8))
        return url
    }()

    static func trace(_ message: String) {
        let stamped = "\(Date()) \(message)\n"
        guard let data = stamped.data(using: .utf8) else { return }
        if FileManager.default.fileExists(atPath: traceURL.path) {
            if let handle = try? FileHandle(forWritingTo: traceURL) {
                handle.seekToEndOfFile()
                handle.write(data)
                try? handle.close()
            }
        } else {
            try? data.write(to: traceURL)
        }
    }

    // MARK: Internals

    private func beginDrag(with event: NSEvent) {
        let pbItem = NSPasteboardItem()
        let imageType = NSPasteboard.PasteboardType(payload.utiIdentifier)
        let genericImageType = NSPasteboard.PasteboardType("public.image")

        // Eager image bytes: under the sandbox the session-store file is inside
        // the app container and unreadable by the destination, so a lazily
        // provided fileURL alone leaves Figma without a droppable payload. Put
        // the raw bytes on the pasteboard up front for both the concrete UTI and
        // the generic `public.image` so an image destination accepts them on the
        // first drag. Fall back to lazy provision only if the eager read fails.
        if let bytes = try? Data(contentsOf: payload.sessionStoreURL) {
            pbItem.setData(bytes, forType: imageType)
            pbItem.setData(bytes, forType: genericImageType)
            Self.trace("beginDrag eager bytes=\(bytes.count) utis=[\(payload.utiIdentifier),public.image]")
        } else {
            pbItem.setDataProvider(self, forTypes: [imageType, genericImageType])
            Self.trace("beginDrag eager read FAILED — lazy provider for \(payload.sessionStoreURL.path)")
        }

        // Keep advertising the file URL for file-oriented destinations (e.g.
        // Finder) that can reach the path; cross-container destinations ignore
        // it and use the eager bytes above.
        let urlString = payload.sessionStoreURL.absoluteString
        pbItem.setString(urlString, forType: .fileURL)

        let draggingItem = NSDraggingItem(pasteboardWriter: pbItem)
        let thumb = thumbnailImage() ?? NSImage(size: NSSize(width: 40, height: 40))
        let imageSize = NSSize(width: 40, height: 40)
        draggingItem.setDraggingFrame(NSRect(origin: .zero, size: imageSize), contents: thumb)

        beginDraggingSession(with: [draggingItem], event: event, source: self)
    }

    private func thumbnailImage() -> NSImage? {
        ShelfThumbnailer.shared.thumbnail(for: payload)
    }
}

extension ShelfRowDragView: NSPasteboardItemDataProvider {
    func pasteboard(_ pasteboard: NSPasteboard?, item: NSPasteboardItem, provideDataForType type: NSPasteboard.PasteboardType) {
        if let data = try? Data(contentsOf: payload.sessionStoreURL) {
            Self.trace("provideData type=\(type.rawValue) bytes=\(data.count)")
            item.setData(data, forType: type)
        } else {
            Self.trace("provideData FAILED to read \(payload.sessionStoreURL.path) type=\(type.rawValue)")
        }
    }
}

/// SwiftUI wrapper around `ShelfRowDragView`. Places a transparent drag view
/// on top of the SwiftUI row content — the drag view captures mouse events
/// and starts the drag session, the row underneath handles rendering.
struct ShelfRowDragOverlay: NSViewRepresentable {
    let payload: ShelfMediaPayload
    let onDragConsumed: () -> Void

    func makeNSView(context: Context) -> ShelfRowDragView {
        ShelfRowDragView(payload: payload, onDragConsumed: onDragConsumed)
    }

    func updateNSView(_ nsView: ShelfRowDragView, context: Context) {
        // Static — payload and callback are recreated with the view when
        // rank/payload changes because the parent identifies rows by
        // `payload.id`.
    }
}
