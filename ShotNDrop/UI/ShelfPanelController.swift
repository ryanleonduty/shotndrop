import AppKit
import SwiftUI
import Combine
import UniformTypeIdentifiers

/// Non-activating always-on-top borderless movable panel. Single window that
/// morphs between a minimized inventory header bar and the fully expanded
/// inventory tray in place — hover-to-preview, click-to-toggle, ESC to
/// collapse.
@MainActor
public final class ShelfPanelController: NSObject {
    public static let dragHysteresisPoints: CGFloat = 4
    /// Hold time for `ACQUIRED` / rejection labels before reverting to the
    /// idle chip. Deliberately longer than the plan's 240ms so the state is
    /// legible instead of a blip.
    public static let flashDuration: TimeInterval = 0.9

    public static let acceptedDraggedTypes: [NSPasteboard.PasteboardType] = [
        .fileURL,
        .tiff,
        .png,
        NSPasteboard.PasteboardType("com.apple.pasteboard.promised-file-content-type"),
        NSPasteboard.PasteboardType("com.apple.pasteboard.promised-file-url"),
        NSPasteboard.PasteboardType("com.apple.NSFilePromiseReceiver"),
        NSPasteboard.PasteboardType("public.image")
    ]

    /// Grace window before on-disk bytes are unlinked after `.copy` drag-out.
    /// Chromium/Electron destinations read the file asynchronously after the
    /// drop event fires, so synchronous delete races and produces
    /// `FileReader` `ProgressEvent` failures.
    public static let consumeDeleteGrace: TimeInterval = 30
    /// Keeps a fitting panel fully visible while dragging; oversized panels
    /// remain anchored to the visible top and right edges.
    static func clampedOrigin(
        _ origin: NSPoint,
        panelSize: NSSize,
        screenFrame: NSRect
    ) -> NSPoint {
        let maximumX = screenFrame.maxX - panelSize.width
        let minimumX = min(screenFrame.minX, maximumX)
        let maximumY = screenFrame.maxY - panelSize.height
        let minimumY = min(screenFrame.minY, maximumY)
        return NSPoint(
            x: min(max(origin.x, minimumX), maximumX),
            y: min(max(origin.y, minimumY), maximumY)
        )
    }

    /// Minimized dimensions — the compact pixel chip. Smaller than the
    /// expanded tray; the controller shifts the panel's horizontal origin
    /// on expand so the chip's screen side (left or right) stays anchored.
    private static var minimizedWidth: CGFloat { PixelDesign.Geometry.chipWidth }
    private static var minimizedHeight: CGFloat { PixelDesign.Geometry.chipHeight }

    public let panel: ShelfPanel
    let hostingView: ShelfHostingView

    public let inventory: ShelfInventory
    public let sessionStore: ShelfSessionStore
    public let validator: ShelfMediaValidator

    private var slotState: ShelfSlotView.State
    private var mode: ShelfContainerView.Mode = .minimized
    private var autoExpandedFromHover: Bool = false
    /// Bottom-left origin of the minimized bar. Persisted across expand/
    /// collapse so the bar always returns to the same on-screen position.
    private var barOrigin: NSPoint = .zero
    /// Which horizontal edge of the chip was anchored to the expanded
    /// panel — determines how to reverse-map a drag of the expanded panel
    /// back onto `barOrigin`.
    private enum HorizontalAnchor { case leading, trailing }
    private var expandedHorizontalAnchor: HorizontalAnchor = .trailing
    private var outsideClickMonitor: Any?

    /// While a drag is hovering, macOS may fire `draggingExited` transiently
    /// as animated frame changes shift the drop target's geometry.
    /// `pendingHoverCollapse` schedules the collapse and gets cancelled if
    /// `draggingEntered` re-fires within the debounce window.
    private var pendingHoverCollapse: DispatchWorkItem?
    private static let hoverExitDebounce: TimeInterval = 0.15

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
            contentRect: NSRect(x: 0, y: 0, width: Self.minimizedWidth, height: Self.minimizedHeight),
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

        let initialContainer = ShelfContainerView(
            mode: .minimized,
            slotState: .idleEmpty(count: 0),
            payloads: [],
            maxTrayHeight: 0,
            onRowDragConsumed: { _ in },
            onEscape: {}
        )
        self.hostingView = ShelfHostingView(rootView: initialContainer)
        hostingView.frame = NSRect(x: 0, y: 0, width: Self.minimizedWidth, height: Self.minimizedHeight)
        panel.contentView = hostingView
        panel.registerForDraggedTypes(ShelfPanelController.acceptedDraggedTypes)

        super.init()

        hostingView.controller = self
        panel.controller = self
    }

    // MARK: Show / hide

    public func showAtDefaultPosition() {
        if let screen = NSScreen.main {
            let visible = screen.visibleFrame
            let x = visible.maxX - Self.minimizedWidth - 16
            let y = visible.midY - Self.minimizedHeight / 2
            barOrigin = NSPoint(x: x, y: y)
            panel.setFrameOrigin(barOrigin)
        } else {
            barOrigin = panel.frame.origin
        }
        panel.orderFrontRegardless()
        renderContainer()
    }

    // MARK: Rendering

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

    /// Resets `slotState` to the current idle state and re-renders the
    /// container in whatever mode the panel currently occupies.
    public func renderSlot() {
        slotState = computeIdleState()
        renderContainer()
    }

    private func renderContainer() {
        let payloads = inventory.readyPayloads
        let container = ShelfContainerView(
            mode: mode,
            slotState: slotState,
            payloads: payloads,
            maxTrayHeight: currentMaxTrayRowsHeight(),
            onRowDragConsumed: { [weak self] id in
                Task { @MainActor in self?.consumeRow(id: id) }
            },
            onEscape: { [weak self] in
                self?.collapse()
            }
        )
        hostingView.rootView = container
    }

    private func currentMaxTrayRowsHeight() -> CGFloat {
        let screenHeight = panel.screen?.visibleFrame.height ?? NSScreen.main?.visibleFrame.height ?? 900
        let cap = 0.6 * screenHeight - PixelDesign.Geometry.trayHeaderHeight - PixelDesign.Geometry.trayFooterHeight
        return max(60, cap)
    }

    // MARK: Expand / collapse

    public var isExpanded: Bool { mode != .minimized }

    var isExpandedBelow: Bool { mode == .expandedBelow }

    var minimizedFrame: NSRect {
        NSRect(
            origin: barOrigin,
            size: NSSize(width: Self.minimizedWidth, height: Self.minimizedHeight)
        )
    }

    /// Height of the tray body (rows + footer). Header is not included here —
    /// in expanded mode the header sits either above or below this block.
    private func computedBodyHeight(
        screenFrame overrideScreenFrame: NSRect? = nil,
        barOriginY overrideBarOriginY: CGFloat? = nil
    ) -> CGFloat {
        let count = inventory.readyPayloads.count
        let rows: CGFloat
        if count == 0 {
            rows = 120
        } else {
            let uncapped = CGFloat(count) * PixelDesign.Geometry.trayRowHeight
            let screenHeight = overrideScreenFrame?.height
                ?? panel.screen?.visibleFrame.height
                ?? NSScreen.main?.visibleFrame.height
                ?? 900
            let cap = 0.6 * screenHeight - PixelDesign.Geometry.trayHeaderHeight - PixelDesign.Geometry.trayFooterHeight
            rows = min(uncapped, max(60, cap))
        }

        let screenFrame = overrideScreenFrame
            ?? panel.screen?.visibleFrame
            ?? NSScreen.main?.visibleFrame
            ?? .zero
        let barY = overrideBarOriginY ?? barOrigin.y
        let availableBelow = max(0, barY - screenFrame.minY)
        let visibleRows = min(rows, max(0, availableBelow - PixelDesign.Geometry.trayFooterHeight))
        return visibleRows + PixelDesign.Geometry.trayFooterHeight
    }

    /// Resolves the expanded panel's frame + direction.
    /// The expanded panel is `trayWidth` wide, so it's larger than the
    /// minimized chip; horizontal origin shifts so the expanded panel stays
    /// on the same screen side as the chip.
    static func downwardExpandedFrame(
        barOrigin: NSPoint,
        horizontalOrigin: CGFloat,
        screenFrame: NSRect,
        bodyHeight: CGFloat,
        expandedWidth: CGFloat,
        minimizedHeight: CGFloat
    ) -> (frame: NSRect, mode: ShelfContainerView.Mode) {
        let availableBelow = max(0, barOrigin.y - screenFrame.minY)
        let visibleBodyHeight = min(bodyHeight, availableBelow)
        let frame = NSRect(
            x: horizontalOrigin,
            y: barOrigin.y - visibleBodyHeight,
            width: expandedWidth,
            height: minimizedHeight + visibleBodyHeight
        )
        return (frame, .expandedBelow)
    }
    private func resolveExpandedFrame(bodyHeight: CGFloat) -> (frame: NSRect, mode: ShelfContainerView.Mode) {
        let screenFrame = panel.screen?.visibleFrame ?? NSScreen.main?.visibleFrame ?? .zero
        let expandedWidth = PixelDesign.Geometry.trayWidth
        let chipMaxX = barOrigin.x + Self.minimizedWidth

        // Horizontal: prefer trailing (chip.maxX == expanded.maxX) so the
        // expanded panel grows leftward from the chip. Fall back to
        // leading if trailing would clip the screen's left edge.
        let trailingX = chipMaxX - expandedWidth
        let anchor: HorizontalAnchor
        let x: CGFloat
        if trailingX >= screenFrame.minX {
            x = trailingX
            anchor = .trailing
        } else {
            x = barOrigin.x
            anchor = .leading
        }
        expandedHorizontalAnchor = anchor

        // Always open downward. The helper caps the body if the chip is near
        // the bottom edge without mutating the minimized chip's origin.
        return Self.downwardExpandedFrame(
            barOrigin: barOrigin,
            horizontalOrigin: x,
            screenFrame: screenFrame,
            bodyHeight: bodyHeight,
            expandedWidth: expandedWidth,
            minimizedHeight: Self.minimizedHeight
        )
    }

    /// Panel resize animation duration for click-driven expand/collapse
    /// paths. Hover-driven auto-expand/collapse skip animation entirely to
    /// avoid the geometry-churn / drop-target-jitter loop.
    private static let frameAnimationDuration: TimeInterval = 0.18

    /// Expand the panel to include the tray body in-place.
    public func expand(animated: Bool = true, makeKey: Bool = true) {
        guard !isExpanded else { return }
        let bodyHeight = computedBodyHeight()
        let (newFrame, direction) = resolveExpandedFrame(bodyHeight: bodyHeight)
        mode = direction
        setPanelFrame(newFrame, animated: animated)
        renderContainer()
        if makeKey {
            panel.makeKey()
        }
        installOutsideClickMonitor()
    }

    /// Collapse back to the minimized header bar.
    public func collapse(animated: Bool = true) {
        guard isExpanded else { return }
        let shouldResignKey = panel.isKeyWindow
        mode = .minimized
        autoExpandedFromHover = false
        removeOutsideClickMonitor()
        let newFrame = NSRect(origin: barOrigin,
                              size: NSSize(width: Self.minimizedWidth, height: Self.minimizedHeight))
        setPanelFrame(newFrame, animated: animated)
        renderContainer()
        if shouldResignKey {
            panel.resignKey()
        }
    }

    private func setPanelFrame(_ newFrame: NSRect, animated: Bool) {
        if animated {
            NSAnimationContext.runAnimationGroup { context in
                context.duration = Self.frameAnimationDuration
                context.timingFunction = CAMediaTimingFunction(name: .easeInEaseOut)
                context.allowsImplicitAnimation = true
                panel.animator().setFrame(newFrame, display: true)
            }
        } else {
            panel.setFrame(newFrame, display: true, animate: false)
        }
    }

    private func installOutsideClickMonitor() {
        guard outsideClickMonitor == nil else { return }
        outsideClickMonitor = NSEvent.addGlobalMonitorForEvents(
            matching: [.leftMouseDown, .rightMouseDown]
        ) { [weak self] _ in
            Task { @MainActor in self?.collapse() }
        }
    }

    private func removeOutsideClickMonitor() {
        if let outsideClickMonitor {
            NSEvent.removeMonitor(outsideClickMonitor)
            self.outsideClickMonitor = nil
        }
    }

    // MARK: Slot interactions

    func handleSlotClick() {
        if isExpanded {
            collapse()
        } else {
            expand()
        }
    }

    /// Updates the stored chip origin whenever the panel is dragged —
    /// whether currently minimized or expanded. When expanded, reverses
    /// the expand math so `barOrigin` matches where the chip would sit if
    /// we collapsed right now.
    func panelSizeForDrag(screenFrame: NSRect) -> NSSize {
        guard isExpanded else {
            return NSSize(width: Self.minimizedWidth, height: Self.minimizedHeight)
        }
        return NSSize(
            width: PixelDesign.Geometry.trayWidth,
            height: Self.minimizedHeight
                + computedBodyHeight(screenFrame: screenFrame, barOriginY: screenFrame.maxY)
        )
    }

    static func dragAnchorYAdjustment(
        oldHeight: CGFloat,
        targetHeight: CGFloat,
        anchorsTopEdge: Bool
    ) -> CGFloat {
        anchorsTopEdge ? oldHeight - targetHeight : 0
    }

    static func projectedDragOrigin(
        mouseGlobal: NSPoint,
        localAnchor: NSPoint,
        oldPanelSize: NSSize,
        targetPanelSize: NSSize,
        screenFrame: NSRect,
        anchorsTopEdge: Bool
    ) -> NSPoint {
        let adjustment = dragAnchorYAdjustment(
            oldHeight: oldPanelSize.height,
            targetHeight: targetPanelSize.height,
            anchorsTopEdge: anchorsTopEdge
        )
        let proposedOrigin = NSPoint(
            x: mouseGlobal.x - localAnchor.x,
            y: mouseGlobal.y - (localAnchor.y - adjustment)
        )
        return clampedOrigin(proposedOrigin, panelSize: targetPanelSize, screenFrame: screenFrame)
    }

    static func shouldRefreshDragAnchor(
        proposedOrigin: NSPoint,
        clampedOrigin: NSPoint,
        oldPanelSize: NSSize,
        targetPanelSize: NSSize
    ) -> Bool {
        clampedOrigin != proposedOrigin
            || abs(oldPanelSize.width - targetPanelSize.width) > 0.5
            || abs(oldPanelSize.height - targetPanelSize.height) > 0.5
    }

    func dragAnchorYAdjustment(for targetSize: NSSize) -> CGFloat {
        Self.dragAnchorYAdjustment(
            oldHeight: panel.frame.height,
            targetHeight: targetSize.height,
            anchorsTopEdge: mode == .expandedBelow
        )
    }

    func handleSlotDragMoved(
        to panelOrigin: NSPoint,
        screenFrame: NSRect,
        targetSize: NSSize
    ) {
        let chipSize = NSSize(width: Self.minimizedWidth, height: Self.minimizedHeight)
        if !isExpanded {
            barOrigin = Self.clampedOrigin(panelOrigin, panelSize: chipSize, screenFrame: screenFrame)
            return
        }

        let dx: CGFloat
        switch expandedHorizontalAnchor {
        case .trailing: dx = PixelDesign.Geometry.trayWidth - Self.minimizedWidth
        case .leading: dx = 0
        }
        let resizedBodyHeight = max(0, targetSize.height - Self.minimizedHeight)
        let sizeChanged = abs(panel.frame.width - targetSize.width) > 0.5
            || abs(panel.frame.height - targetSize.height) > 0.5

        let candidateDy: CGFloat
        switch mode {
        case .expandedBelow: candidateDy = resizedBodyHeight
        case .expandedAbove, .minimized: candidateDy = 0
        }
        let candidate = NSPoint(x: panelOrigin.x + dx, y: panelOrigin.y + candidateDy)
        barOrigin = Self.clampedOrigin(candidate, panelSize: chipSize, screenFrame: screenFrame)

        guard sizeChanged else { return }
        // Preserve the pointer's local position while resizing across displays.
        setPanelFrame(NSRect(origin: panelOrigin, size: targetSize), animated: false)
        renderContainer()
    }
    func handleSlotRightClick(at point: NSPoint) {
        if isExpanded { collapse() }
        let menu = NSMenu()
        let clearItem = NSMenuItem(title: "Clear", action: #selector(clearInventory), keyEquivalent: "")
        clearItem.target = self
        clearItem.isEnabled = !inventory.isEmpty
        menu.addItem(clearItem)
        let quitItem = NSMenuItem(title: "Quit", action: #selector(quitApp), keyEquivalent: "")
        quitItem.target = self
        menu.addItem(quitItem)
        menu.popUp(positioning: nil, at: point, in: hostingView)
    }

    @objc private func clearInventory() {
        inventory.clear()
        sessionStore.clearContents()
        if isExpanded {
            collapse()
        } else {
            renderSlot()
        }
    }

    @objc private func quitApp() {
        NSApp.terminate(nil)
    }

    // MARK: Consume

    private func consumeRow(id: UUID) {
        _ = inventory.remove(id: id)
        ShelfThumbnailer.shared.invalidate(id: id)

        let store = self.sessionStore
        DispatchQueue.global(qos: .background)
            .asyncAfter(deadline: .now() + Self.consumeDeleteGrace) {
                store.remove(id: id)
            }

        slotState = computeIdleState()
        if isExpanded {
            let bodyHeight = computedBodyHeight()
            let direction = mode
            let width = Self.minimizedWidth
            let height = Self.minimizedHeight + bodyHeight
            let x = barOrigin.x
            let y: CGFloat
            switch direction {
            case .expandedBelow: y = barOrigin.y - bodyHeight
            case .expandedAbove: y = barOrigin.y
            case .minimized: y = barOrigin.y
            }
            panel.setFrame(NSRect(x: x, y: y, width: width, height: height), display: true, animate: true)
        }
        renderContainer()
    }

    // MARK: Drag-in

    public func draggingEntered(_ sender: NSDraggingInfo) -> NSDragOperation {
        let ok = validator.canAccept(dragInfo: sender)
        guard ok else { return [] }
        // Cancel any pending collapse from a transient exit — the drag is
        // back inside the panel.
        pendingHoverCollapse?.cancel()
        pendingHoverCollapse = nil

        slotState = .dragHover(hadItems: !inventory.isEmpty)
        if !isExpanded {
            autoExpandedFromHover = true
            expand(animated: false, makeKey: false)  // snap during drag to avoid jitter
        } else {
            renderContainer()
        }
        return .copy
    }

    public func draggingExited(_ sender: NSDraggingInfo?) {
        // Debounce exit — the frame animation and macOS drop-target
        // re-evaluation can fire spurious exits while the mouse is still
        // inside the panel. If a real drop or a real re-enter happens, the
        // pending item gets cancelled first.
        pendingHoverCollapse?.cancel()
        let work = DispatchWorkItem { [weak self] in
            guard let self else { return }
            self.pendingHoverCollapse = nil
            if self.autoExpandedFromHover {
                self.collapse()
            } else {
                self.slotState = self.computeIdleState()
                self.renderContainer()
            }
        }
        // Snap-collapse when the exit debounce elapses — the drag is truly
        // gone, we want the panel back to the chip immediately (no
        // half-way visual during a re-drag).
        let collapseWork = DispatchWorkItem { [weak self] in
            guard let self else { return }
            self.pendingHoverCollapse = nil
            if self.autoExpandedFromHover {
                self.collapse(animated: false)
            } else {
                self.slotState = self.computeIdleState()
                self.renderContainer()
            }
        }
        pendingHoverCollapse = collapseWork
        _ = work // legacy binding safely dropped
        DispatchQueue.main.asyncAfter(deadline: .now() + Self.hoverExitDebounce, execute: collapseWork)
    }

    public func performDragOperation(_ sender: NSDraggingInfo) -> Bool {
        // A real drop preempts any pending exit-collapse.
        pendingHoverCollapse?.cancel()
        pendingHoverCollapse = nil
        guard validator.canAccept(dragInfo: sender) else { return false }

        let pasteboard = sender.draggingPasteboard

        var snapshot: Data?
        var utiIdentifier: String = "public.png"
        var preferredExtension: String = "png"
        var originalFilename: String = "capture.png"

        if let url = firstFileURL(on: pasteboard) {
            do {
                snapshot = try Data(contentsOf: url, options: .mappedIfSafe)
                originalFilename = url.lastPathComponent
                utiIdentifier = (try? url.resourceValues(forKeys: [.contentTypeKey]))?.contentType?.identifier ?? "public.data"
                preferredExtension = url.pathExtension.isEmpty ? "png" : url.pathExtension
            } catch {
                snapshot = nil
            }
        }

        if snapshot == nil, let (data, ext, uti) = readRawImageBytes(from: pasteboard) {
            snapshot = data
            preferredExtension = ext
            utiIdentifier = uti
            originalFilename = "Screenshot.\(ext)"
        }

        guard let bytes = snapshot else {
            triggerRejection(.unavailable)
            return false
        }

        guard let pendingID = inventory.reservePending() else {
            triggerRejection(.shelfFull)
            return true
        }

        slotState = .pending(count: inventory.count)
        renderContainer()

        let capturedAt = Date()
        let uti = utiIdentifier
        let ext = preferredExtension
        let originalFilenameBinding = originalFilename
        let snapshotBytes = bytes

        let validator = self.validator
        let store = self.sessionStore
        let existingFingerprints = inventory.fingerprints()
        Task.detached {
            do {
                let destination = try store.write(bytes: snapshotBytes, id: pendingID, preferredExtension: ext)
                let payload = try validator.finalize(
                    snapshot: snapshotBytes,
                    originalFilename: originalFilenameBinding,
                    capturedAt: capturedAt,
                    sessionStoreURL: destination,
                    utiIdentifier: uti,
                    id: pendingID
                )
                if existingFingerprints.contains(payload.fingerprint) {
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

    private func readRawImageBytes(from pasteboard: NSPasteboard) -> (Data, String, String)? {
        let priorityOrder: [(NSPasteboard.PasteboardType, String, String)] = [
            (.png, "png", "public.png"),
            (NSPasteboard.PasteboardType("public.heic"), "heic", "public.heic"),
            (NSPasteboard.PasteboardType("public.jpeg"), "jpg", "public.jpeg"),
            (NSPasteboard.PasteboardType("com.compuserve.gif"), "gif", "com.compuserve.gif"),
            (.tiff, "tiff", "public.tiff")
        ]
        for (type, ext, uti) in priorityOrder {
            if let data = pasteboard.data(forType: type), !data.isEmpty {
                return (data, ext, uti)
            }
        }
        return nil
    }

    private func triggerDropSuccess() {
        slotState = .dropSuccess(count: inventory.count)
        if isExpanded {
            // Recompute the expanded frame for the added row's height.
            let bodyHeight = computedBodyHeight()
            let (newFrame, direction) = resolveExpandedFrame(bodyHeight: bodyHeight)
            mode = direction
            setPanelFrame(newFrame, animated: true)
        }
        renderContainer()

        let wasAuto = autoExpandedFromHover
        DispatchQueue.main.asyncAfter(deadline: .now() + Self.flashDuration) { [weak self] in
            guard let self else { return }
            self.slotState = self.computeIdleState()
            if wasAuto { self.collapse(animated: true) } else { self.renderContainer() }
        }
    }

    private func triggerRejection(_ reason: ShelfSlotView.RejectionReason) {
        slotState = .rejection(reason)
        renderContainer()
        DispatchQueue.main.asyncAfter(deadline: .now() + Self.flashDuration) { [weak self] in
            guard let self else { return }
            self.slotState = self.computeIdleState()
            self.renderContainer()
        }
    }
}

/// Panel subclass that accepts becoming key even though it is non-activating.
public final class ShelfPanel: NSPanel {
    weak var controller: ShelfPanelController?
    public override var canBecomeKey: Bool { true }
    public override var canBecomeMain: Bool { false }

    public override func keyDown(with event: NSEvent) {
        if event.keyCode == 53 {
            controller?.collapse()
            return
        }
        super.keyDown(with: event)
    }
}

/// Hosting view that owns:
/// * mouse-down tracking for click-vs-drag hysteresis on the whole panel
/// * NSDraggingDestination forwarding to `ShelfPanelController`
final class ShelfHostingView: NSHostingView<ShelfContainerView> {
    weak var controller: ShelfPanelController?

    private var mouseDownPoint: NSPoint?
    private var didExceedThreshold: Bool = false

    required init(rootView: ShelfContainerView) {
        super.init(rootView: rootView)
        registerForDraggedTypes(ShelfPanelController.acceptedDraggedTypes)
    }

    @MainActor @available(*, unavailable) required init?(coder: NSCoder) {
        fatalError("init(coder:) not supported")
    }

    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        registerForDraggedTypes(ShelfPanelController.acceptedDraggedTypes)
        window?.registerForDraggedTypes(ShelfPanelController.acceptedDraggedTypes)
    }

    override func mouseDown(with event: NSEvent) {
        mouseDownPoint = event.locationInWindow
        didExceedThreshold = false
    }

    override func mouseDragged(with event: NSEvent) {
        guard let start = mouseDownPoint, let window else { return }
        let currentWindow = event.locationInWindow
        let dx = currentWindow.x - start.x
        let dy = currentWindow.y - start.y
        let distance = sqrt(dx * dx + dy * dy)
        if !didExceedThreshold && distance >= ShelfPanelController.dragHysteresisPoints {
            didExceedThreshold = true
        }
        if didExceedThreshold {
            let mouseGlobal = NSEvent.mouseLocation
            let screenFrame = NSScreen.screens.first { $0.frame.contains(mouseGlobal) }?.visibleFrame
                ?? window.screen?.visibleFrame
                ?? NSScreen.main?.visibleFrame
                ?? NSRect(origin: window.frame.origin, size: window.frame.size)
            let targetSize = controller?.panelSizeForDrag(screenFrame: screenFrame)
                ?? window.frame.size
            let anchorsTopEdge = controller?.isExpandedBelow ?? false
            let anchorAdjustment = ShelfPanelController.dragAnchorYAdjustment(
                oldHeight: window.frame.height,
                targetHeight: targetSize.height,
                anchorsTopEdge: anchorsTopEdge
            )
            let proposedOrigin = NSPoint(
                x: mouseGlobal.x - start.x,
                y: mouseGlobal.y - (start.y - anchorAdjustment)
            )
            let newOrigin = ShelfPanelController.clampedOrigin(
                proposedOrigin,
                panelSize: targetSize,
                screenFrame: screenFrame
            )
            let needsAnchorRefresh = ShelfPanelController.shouldRefreshDragAnchor(
                proposedOrigin: proposedOrigin,
                clampedOrigin: newOrigin,
                oldPanelSize: window.frame.size,
                targetPanelSize: targetSize
            )
            window.setFrameOrigin(newOrigin)
            controller?.handleSlotDragMoved(
                to: newOrigin,
                screenFrame: screenFrame,
                targetSize: targetSize
            )
            if needsAnchorRefresh {
                mouseDownPoint = window.convertPoint(fromScreen: mouseGlobal)
            }
        }
    }

    override func mouseUp(with event: NSEvent) {
        defer {
            mouseDownPoint = nil
        }
        if !didExceedThreshold {
            controller?.handleSlotClick()
        }
        didExceedThreshold = false
    }

    override func rightMouseDown(with event: NSEvent) {
        let point = convert(event.locationInWindow, from: nil)
        controller?.handleSlotRightClick(at: point)
    }

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
