import AppKit
import SwiftUI
import Combine
import UniformTypeIdentifiers

/// Non-activating always-on-top borderless movable panel with the pixel drop
/// slot inside. Handles:
/// * 4pt click-vs-drag hysteresis on the slot chrome
/// * NSDraggingDestination two-phase drop (fast canAccept sync, then off-main
///   copy + main-actor resolve)
/// * Tray presentation (four-anchor placement) with ESC / outside-click
///   dismissal
/// * Right-click menu (CLEAR gated on non-empty, QUIT)
@MainActor
public final class ShelfPanelController: NSObject {
    public static let dragHysteresisPoints: CGFloat = 4
    public static let flashDuration: TimeInterval = 0.240

    public let panel: ShelfPanel
    let hostingView: ShelfHostingView

    public let inventory: ShelfInventory
    public let sessionStore: ShelfSessionStore
    public let validator: ShelfMediaValidator

    private var slotState: ShelfSlotView.State
    private var trayWindow: TrayPanel?
    private var outsideMonitor: Any?
    private var slotAnchor: NSPoint = .zero

    public init(
        inventory: ShelfInventory,
        sessionStore: ShelfSessionStore,
        validator: ShelfMediaValidator = ShelfMediaValidator()
    ) {
        self.inventory = inventory
        self.sessionStore = sessionStore
        self.validator = validator
        self.slotState = .idleEmpty(count: 0)

        let panel = ShelfPanel(
            contentRect: NSRect(x: 0, y: 0, width: 96, height: 96),
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )
        panel.isFloatingPanel = true
        panel.level = .floating
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        panel.becomesKeyOnlyIfNeeded = true
        panel.hidesOnDeactivate = false
        panel.hasShadow = false
        panel.isMovable = false
        panel.isMovableByWindowBackground = false
        panel.backgroundColor = .clear
        panel.isOpaque = false
        self.panel = panel

        self.hostingView = ShelfHostingView(rootView: ShelfSlotView(state: .idleEmpty(count: 0)))
        hostingView.frame = NSRect(x: 0, y: 0, width: 96, height: 96)
        panel.contentView = hostingView
        panel.registerForDraggedTypes([.fileURL])

        super.init()

        hostingView.controller = self
        panel.controller = self
    }

    // MARK: Show / hide

    public func showAtDefaultPosition() {
        if let screen = NSScreen.main {
            let visible = screen.visibleFrame
            let x = visible.maxX - 96 - 16
            let y = visible.midY - 48
            panel.setFrameOrigin(NSPoint(x: x, y: y))
        }
        panel.orderFrontRegardless()
        renderSlot()
    }

    // MARK: Slot state

    public func renderSlot() {
        let state = computeIdleState()
        slotState = state
        hostingView.rootView = ShelfSlotView(state: state)
    }

    private func computeIdleState() -> ShelfSlotView.State {
        if inventory.isEmpty { return .idleEmpty(count: 0) }
        let peek = firstAvailablePeek()
        return .idleHolding(count: inventory.count, topPeek: peek)
    }

    private func firstAvailablePeek() -> NSImage? {
        for slot in inventory.slots {
            if case let .ready(payload) = slot.status,
               let image = NSImage(contentsOf: payload.sessionStoreURL) {
                return image
            }
        }
        return nil
    }

    // MARK: Slot interactions

    /// Called by the hosting view on mouse-up when displacement stayed below
    /// the 4pt hysteresis threshold — treat as a click, toggle the tray.
    func handleSlotClick() {
        if trayWindow != nil {
            dismissTray()
        } else {
            presentTray()
        }
    }

    /// Called by the hosting view when the pointer moved past the threshold
    /// during a mouse-down — drag the panel with the pointer.
    func handleSlotDrag(delta: CGSize) {
        var origin = panel.frame.origin
        origin.x += delta.width
        origin.y -= delta.height
        panel.setFrameOrigin(origin)
    }

    func handleSlotRightClick(at point: NSPoint) {
        if trayWindow != nil { dismissTray() }
        let menu = NSMenu()
        let clearItem = NSMenuItem(title: "CLEAR", action: #selector(clearInventory), keyEquivalent: "")
        clearItem.target = self
        clearItem.isEnabled = !inventory.isEmpty
        menu.addItem(clearItem)
        let quitItem = NSMenuItem(title: "QUIT", action: #selector(quitApp), keyEquivalent: "")
        quitItem.target = self
        menu.addItem(quitItem)
        menu.popUp(positioning: nil, at: point, in: hostingView)
    }

    @objc private func clearInventory() {
        inventory.clear()
        sessionStore.clearContents()
        renderSlot()
    }

    @objc private func quitApp() {
        NSApp.terminate(nil)
    }

    // MARK: Tray

    public var isTrayOpen: Bool { trayWindow != nil }

    public func presentTray() {
        guard trayWindow == nil else { return }
        let payloads = inventory.readyPayloads
        let tray = TrayPanel(
            contentRect: NSRect(x: 0, y: 0, width: 240, height: 80),
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )
        tray.isFloatingPanel = true
        tray.level = .floating
        tray.hasShadow = true
        tray.backgroundColor = .clear
        tray.isOpaque = false

        let screenHeight = panel.screen?.visibleFrame.height ?? NSScreen.main?.visibleFrame.height ?? 900
        let maxRowsHeight = max(60, screenHeight * 0.6 - PixelDesign.Geometry.trayHeaderHeight - PixelDesign.Geometry.trayFooterHeight)

        let view = ShelfTrayView(
            payloads: payloads,
            maxHeight: maxRowsHeight,
            onRowDragConsumed: { [weak self] id in
                Task { @MainActor in
                    self?.consumeRow(id: id)
                }
            },
            onEscape: { [weak self] in
                self?.dismissTray()
            }
        )
        let hosting = NSHostingView(rootView: view)
        hosting.frame = NSRect(x: 0, y: 0, width: 240, height: hosting.fittingSize.height)
        tray.setContentSize(hosting.fittingSize)
        tray.contentView = hosting

        positionTray(tray)
        tray.orderFrontRegardless()
        trayWindow = tray

        outsideMonitor = NSEvent.addGlobalMonitorForEvents(matching: [.leftMouseDown, .rightMouseDown]) { [weak self] _ in
            Task { @MainActor in
                self?.dismissTray()
            }
        }
    }

    private func positionTray(_ tray: NSPanel) {
        let slotFrame = panel.frame
        let screenFrame = panel.screen?.visibleFrame ?? NSScreen.main?.visibleFrame ?? .zero
        let traySize = tray.frame.size

        let anchor = TrayAnchor.resolve(slotFrame: slotFrame, screenFrame: screenFrame, traySize: traySize)
        let origin = anchor.origin(slotFrame: slotFrame, traySize: traySize)
        tray.setFrame(NSRect(origin: origin, size: traySize), display: true)
    }

    public func dismissTray() {
        if let outsideMonitor {
            NSEvent.removeMonitor(outsideMonitor)
            self.outsideMonitor = nil
        }
        trayWindow?.orderOut(nil)
        trayWindow = nil
    }

    private func consumeRow(id: UUID) {
        _ = inventory.remove(id: id)
        sessionStore.remove(id: id)
        ShelfThumbnailer.shared.invalidate(id: id)
        renderSlot()
        if isTrayOpen {
            dismissTray()
            presentTray()
        }
    }

    // MARK: Drag-in

    public func draggingEntered(_ sender: NSDraggingInfo) -> NSDragOperation {
        let ok = validator.canAccept(dragInfo: sender)
        guard ok else { return [] }
        slotState = .dragHover(hadItems: !inventory.isEmpty)
        hostingView.rootView = ShelfSlotView(state: slotState)
        return .copy
    }

    public func draggingExited(_ sender: NSDraggingInfo?) {
        renderSlot()
    }

    public func performDragOperation(_ sender: NSDraggingInfo) -> Bool {
        guard validator.canAccept(dragInfo: sender) else { return false }
        guard let url = firstFileURL(on: sender.draggingPasteboard) else { return false }

        // Snapshot bytes synchronously before returning — macOS may reap the
        // source URL immediately after this method returns.
        let snapshot: Data
        do {
            snapshot = try Data(contentsOf: url, options: .mappedIfSafe)
        } catch {
            triggerRejection(.unavailable)
            return false
        }

        guard let pendingID = inventory.reservePending() else {
            triggerRejection(.shelfFull)
            return true
        }

        slotState = .pending(count: inventory.count)
        hostingView.rootView = ShelfSlotView(state: slotState)

        let originalFilename = url.lastPathComponent
        let capturedAt = Date()
        let uti = (try? url.resourceValues(forKeys: [.contentTypeKey]))?.contentType?.identifier ?? "public.data"
        let ext = url.pathExtension

        let validator = self.validator
        let store = self.sessionStore
        let existingFingerprints = inventory.fingerprints()
        Task.detached {
            do {
                let destination = try store.write(bytes: snapshot, id: pendingID, preferredExtension: ext)
                let payload = try validator.finalize(
                    snapshot: snapshot,
                    originalFilename: originalFilename,
                    capturedAt: capturedAt,
                    sessionStoreURL: destination,
                    utiIdentifier: uti,
                    id: pendingID
                )
                if existingFingerprints.contains(payload.fingerprint) {
                    // Duplicate — undo the write.
                    store.remove(id: pendingID)
                    await MainActor.run {
                        _ = self.inventory.fail(id: pendingID, reason: .duplicate)
                        self.triggerRejection(.duplicate)
                    }
                    return
                }
                await MainActor.run {
                    _ = self.inventory.resolve(id: pendingID, with: payload)
                    self.triggerDropSuccess()
                }
            } catch {
                await MainActor.run {
                    _ = self.inventory.fail(id: pendingID, reason: .copyFailed)
                    self.triggerRejection(.unavailable)
                }
            }
        }

        return true
    }

    private func firstFileURL(on pasteboard: NSPasteboard) -> URL? {
        guard let urls = pasteboard.readObjects(forClasses: [NSURL.self], options: nil) as? [URL] else {
            return nil
        }
        return urls.first(where: { url in
            let ext = url.pathExtension.lowercased()
            return ["png", "jpg", "jpeg", "heic", "tif", "tiff", "webp", "gif"].contains(ext)
        }) ?? urls.first
    }

    private func triggerDropSuccess() {
        slotState = .dropSuccess(count: inventory.count)
        hostingView.rootView = ShelfSlotView(state: slotState)
        DispatchQueue.main.asyncAfter(deadline: .now() + Self.flashDuration) { [weak self] in
            self?.renderSlot()
        }
    }

    private func triggerRejection(_ reason: ShelfSlotView.RejectionReason) {
        slotState = .rejection(reason)
        hostingView.rootView = ShelfSlotView(state: slotState)
        DispatchQueue.main.asyncAfter(deadline: .now() + Self.flashDuration) { [weak self] in
            self?.renderSlot()
        }
    }
}

/// Panel subclass that accepts becoming key even though it is non-activating.
public final class ShelfPanel: NSPanel {
    weak var controller: ShelfPanelController?
    public override var canBecomeKey: Bool { true }
    public override var canBecomeMain: Bool { false }
}

/// Second panel subclass used for the tray so key handling flows to its
/// hosted view (for ESC dismissal).
public final class TrayPanel: NSPanel {
    public override var canBecomeKey: Bool { true }
    public override var canBecomeMain: Bool { false }
}

/// Hosting view that owns:
/// * mouse-down tracking for click-vs-drag hysteresis
/// * NSDraggingDestination forwarding to `ShelfPanelController`
final class ShelfHostingView: NSHostingView<ShelfSlotView> {
    weak var controller: ShelfPanelController?

    private var mouseDownPoint: NSPoint?
    private var didExceedThreshold: Bool = false
    private var mouseDownWindowOrigin: NSPoint?

    required init(rootView: ShelfSlotView) {
        super.init(rootView: rootView)
    }

    @MainActor @available(*, unavailable) required init?(coder: NSCoder) {
        fatalError("init(coder:) not supported")
    }

    // Ensures the view participates in drag routing.
    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        window?.registerForDraggedTypes([.fileURL])
    }

    // MARK: Mouse

    override func mouseDown(with event: NSEvent) {
        mouseDownPoint = event.locationInWindow
        mouseDownWindowOrigin = window?.frame.origin
        didExceedThreshold = false
    }

    override func mouseDragged(with event: NSEvent) {
        guard let start = mouseDownPoint, let origin = mouseDownWindowOrigin, let window else { return }
        let currentWindow = event.locationInWindow
        let dx = currentWindow.x - start.x
        let dy = currentWindow.y - start.y
        let distance = sqrt(dx * dx + dy * dy)
        if !didExceedThreshold && distance >= ShelfPanelController.dragHysteresisPoints {
            didExceedThreshold = true
        }
        if didExceedThreshold {
            let mouseGlobal = NSEvent.mouseLocation
            let newOrigin = NSPoint(
                x: mouseGlobal.x - start.x,
                y: mouseGlobal.y - start.y
            )
            _ = origin
            window.setFrameOrigin(newOrigin)
        }
    }

    override func mouseUp(with event: NSEvent) {
        defer {
            mouseDownPoint = nil
            mouseDownWindowOrigin = nil
        }
        if !didExceedThreshold {
            controller?.handleSlotClick()
        }
    }

    override func rightMouseDown(with event: NSEvent) {
        let point = convert(event.locationInWindow, from: nil)
        controller?.handleSlotRightClick(at: point)
    }

    // MARK: Drag destination

    override func draggingEntered(_ sender: NSDraggingInfo) -> NSDragOperation {
        controller?.draggingEntered(sender) ?? []
    }

    override func draggingExited(_ sender: NSDraggingInfo?) {
        controller?.draggingExited(sender)
    }

    override func prepareForDragOperation(_ sender: NSDraggingInfo) -> Bool {
        controller?.validator.canAccept(dragInfo: sender) ?? false
    }

    override func performDragOperation(_ sender: NSDraggingInfo) -> Bool {
        controller?.performDragOperation(sender) ?? false
    }
}
