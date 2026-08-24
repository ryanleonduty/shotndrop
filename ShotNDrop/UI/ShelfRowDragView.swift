import AppKit
import SwiftUI
import UniformTypeIdentifiers

/// AppKit drag source that starts a real
/// `beginDraggingSession(with:event:source:)` on mouseDown-plus-drag. The
/// pasteboard writer is an `NSFilePromiseProvider` — macOS asks the
/// destination for a writable directory it can reach (e.g. Figma's shared
/// import scratch), invokes our fileNameForType + writePromise callbacks,
/// and hands the resulting URL to the destination via
/// `event.dataTransfer.files`. This is the only way to hand a real file
/// across a sandbox boundary to a non-sandboxed destination like Figma.
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
        // Eager pasteboard shape:
        //   * `.fileURL`  → the on-disk session-store URL. Chromium/Electron
        //     apps (Figma) only recognize eager file URLs for cross-app
        //     drops.
        //   * `payload.utiIdentifier`, `public.image` → raw bytes for
        //     destinations that consume paste data directly.
        //
        // App-sandbox is OFF for this build; without that the session store
        // lives under `/var/folders/*/T/…` which is globally readable to
        // user-space apps, so the file URL actually resolves for Figma.
        let pbItem = NSPasteboardItem()
        pbItem.setDataProvider(self, forTypes: [
            NSPasteboard.PasteboardType(payload.utiIdentifier),
            NSPasteboard.PasteboardType("public.image")
        ])

        // Write the file URL eagerly so destinations see it in the initial
        // pasteboard enumeration (which is what Chromium's drop cursor
        // resolver uses).
        let urlString = payload.sessionStoreURL.absoluteString
        pbItem.setString(urlString, forType: .fileURL)
        Self.trace("beginDrag advertised fileURL=\(urlString) utis=[\(payload.utiIdentifier),public.image]")

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
