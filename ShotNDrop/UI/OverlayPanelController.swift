import Foundation
import AppKit
import SwiftUI

// MARK: - Pure geometry (testable without an NSPanel)

public enum OverlayCorner: Sendable, Equatable {
    case topTrailing
    case topLeading
    case bottomTrailing
    case bottomLeading
}

public enum OverlayGeometry {
    /// Insets applied to the visible frame before placing the panel.
    public static let visibleInset: CGFloat = 12

    /// Pick the screen that currently contains `cursor`, or fall back to the
    /// main screen and finally the first available.
    public static func screen(
        forCursor cursor: CGPoint,
        in screens: [CGRect]
    ) -> CGRect? {
        if let hit = screens.first(where: { $0.contains(cursor) }) {
            return hit
        }
        return screens.first
    }

    /// Compute the panel frame for a given `size` and `corner`, clamped fully
    /// inside `visibleFrame` (which already excludes Dock/menu bar in AppKit).
    public static func frame(
        size: CGSize,
        corner: OverlayCorner,
        visibleFrame: CGRect
    ) -> CGRect {
        let inset = visibleInset
        // Clamp the size to the visibleFrame so it never exceeds it.
        let w = min(size.width, max(0, visibleFrame.width - inset * 2))
        let h = min(size.height, max(0, visibleFrame.height - inset * 2))
        var origin = CGPoint.zero
        switch corner {
        case .topTrailing:
            origin.x = visibleFrame.maxX - w - inset
            origin.y = visibleFrame.maxY - h - inset
        case .topLeading:
            origin.x = visibleFrame.minX + inset
            origin.y = visibleFrame.maxY - h - inset
        case .bottomTrailing:
            origin.x = visibleFrame.maxX - w - inset
            origin.y = visibleFrame.minY + inset
        case .bottomLeading:
            origin.x = visibleFrame.minX + inset
            origin.y = visibleFrame.minY + inset
        }
        var frame = CGRect(origin: origin, size: CGSize(width: w, height: h))
        // Explicit clamp guards against tiny screens.
        if frame.maxX > visibleFrame.maxX { frame.origin.x = visibleFrame.maxX - frame.width }
        if frame.maxY > visibleFrame.maxY { frame.origin.y = visibleFrame.maxY - frame.height }
        if frame.minX < visibleFrame.minX { frame.origin.x = visibleFrame.minX }
        if frame.minY < visibleFrame.minY { frame.origin.y = visibleFrame.minY }
        return frame
    }
}

// MARK: - Visibility state machine (pure)

public enum VisibilityCause: Sendable, Equatable {
    case newItem
    case menuReopen
    case restore
}

public struct VisibilityState: Sendable, Equatable {
    public var isVisible: Bool = false
    public var timerGeneration: UInt64 = 0
    public var lastCauseAt: Date? = nil
}

public enum VisibilityTransition {
    public static let autoHide: TimeInterval = 30

    /// Apply a "show" cause — cancel prior timer, start a fresh generation.
    public static func onShow(
        _ state: VisibilityState,
        at now: Date,
        cause: VisibilityCause
    ) -> VisibilityState {
        _ = cause
        var next = state
        next.isVisible = true
        next.timerGeneration &+= 1
        next.lastCauseAt = now
        return next
    }

    /// Apply a "hide" instruction; queue is untouched by the caller.
    public static func onHide(_ state: VisibilityState) -> VisibilityState {
        var next = state
        next.isVisible = false
        return next
    }

    /// Should the auto-hide timer fire for this generation and cause fire?
    public static func shouldAutoHide(
        currentGeneration: UInt64,
        firedGeneration: UInt64
    ) -> Bool {
        return currentGeneration == firedGeneration
    }
}

// MARK: - Live controller

@MainActor
public final class OverlayPanelController {
    public var onCopy: ((ScreenshotItem) -> Void)?
    public var onClose: ((ScreenshotItem) -> Void)?

    private var panel: NSPanel?
    private var hostingController: NSHostingController<OverlayContentView>?
    private var state: VisibilityState = VisibilityState()
    private var currentItems: [ScreenshotItem] = []
    private var autoHideTask: DispatchWorkItem?
    private var screenObserver: NSObjectProtocol?

    public init() {}

    public func show(items: [ScreenshotItem]) {
        guard !items.isEmpty else {
            hide()
            return
        }
        self.currentItems = items
        ensurePanel()
        state = VisibilityTransition.onShow(state, at: Date(), cause: .newItem)
        repositionPanel()
        applyItemsToPanel()
        panel?.orderFrontRegardless()
        scheduleAutoHide()
    }

    /// Pause the auto-hide timer (during hover/drag). Restart begins a fresh generation.
    public func pauseAutoHide() {
        autoHideTask?.cancel()
        autoHideTask = nil
    }

    public func restartAutoHide() {
        guard state.isVisible else { return }
        state = VisibilityTransition.onShow(state, at: Date(), cause: .menuReopen)
        scheduleAutoHide()
    }

    public func hide() {
        panel?.orderOut(nil)
        state = VisibilityTransition.onHide(state)
        autoHideTask?.cancel()
        autoHideTask = nil
    }

    public func tearDown() {
        autoHideTask?.cancel()
        autoHideTask = nil
        if let observer = screenObserver {
            NotificationCenter.default.removeObserver(observer)
            screenObserver = nil
        }
        panel?.orderOut(nil)
        panel = nil
        hostingController = nil
        currentItems.removeAll()
    }

    // MARK: - Private

    private func ensurePanel() {
        guard panel == nil else { return }
        let contentSize = CGSize(width: 320, height: 240)
        let p = NSPanel(
            contentRect: CGRect(origin: .zero, size: contentSize),
            styleMask: [.nonactivatingPanel, .borderless, .fullSizeContentView],
            backing: .buffered,
            defer: false
        )
        p.isFloatingPanel = true
        p.hidesOnDeactivate = false
        p.becomesKeyOnlyIfNeeded = true
        p.hasShadow = true
        p.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary]
        p.level = .floating
        p.backgroundColor = .clear
        p.isOpaque = false
        p.worksWhenModal = false

        let view = OverlayContentView(
            items: currentItems,
            onCopy: { [weak self] item in self?.handleCopy(item) },
            onClose: { [weak self] item in self?.handleClose(item) },
            onHoverChange: { [weak self] hovering in
                if hovering {
                    self?.pauseAutoHide()
                } else {
                    self?.restartAutoHide()
                }
            }
        )
        let host = NSHostingController(rootView: view)
        host.view.frame = CGRect(origin: .zero, size: contentSize)
        p.contentViewController = host
        self.panel = p
        self.hostingController = host

        let observer = NotificationCenter.default.addObserver(
            forName: NSApplication.didChangeScreenParametersNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            Task { @MainActor in
                self?.repositionPanel()
            }
        }
        self.screenObserver = observer
    }

    private func repositionPanel() {
        guard let panel else { return }
        let cursor = NSEvent.mouseLocation
        let screens = NSScreen.screens.map(\.visibleFrame)
        guard let visible = OverlayGeometry.screen(forCursor: cursor, in: screens) else { return }
        let size = panel.frame.size
        let frame = OverlayGeometry.frame(size: size, corner: .topTrailing, visibleFrame: visible)
        panel.setFrame(frame, display: true)
    }

    private func applyItemsToPanel() {
        guard let hostingController else { return }
        hostingController.rootView = OverlayContentView(
            items: currentItems,
            onCopy: { [weak self] item in self?.handleCopy(item) },
            onClose: { [weak self] item in self?.handleClose(item) },
            onHoverChange: { [weak self] hovering in
                if hovering {
                    self?.pauseAutoHide()
                } else {
                    self?.restartAutoHide()
                }
            }
        )
    }

    private func scheduleAutoHide() {
        autoHideTask?.cancel()
        let firedGeneration = state.timerGeneration
        let work = DispatchWorkItem { [weak self] in
            guard let self else { return }
            if VisibilityTransition.shouldAutoHide(
                currentGeneration: self.state.timerGeneration,
                firedGeneration: firedGeneration
            ) {
                self.hide()
            }
        }
        autoHideTask = work
        DispatchQueue.main.asyncAfter(deadline: .now() + VisibilityTransition.autoHide, execute: work)
    }

    private func handleCopy(_ item: ScreenshotItem) {
        // Revalidate source availability before publishing to the pasteboard.
        guard (try? item.url.checkResourceIsReachable()) == true else { return }
        let pb = NSPasteboard.general
        pb.clearContents()
        // Primary: file URL. Compatible: image data for pasteboard readers that
        // want the pixels directly (e.g. Slack rich-text targets).
        pb.writeObjects([item.url as NSURL])
        if let image = NSImage(contentsOf: item.url) {
            pb.writeObjects([image])
        }
        onCopy?(item)
    }

    private func handleClose(_ item: ScreenshotItem) {
        onClose?(item)
    }
}
