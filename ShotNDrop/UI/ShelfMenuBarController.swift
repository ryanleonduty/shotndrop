import AppKit
import Combine
/// Owns the menu-bar `NSStatusItem` and its four-item menu:
/// `HIDE/SHOW`, `CLEAR`, `CHECK FOR UPDATES`, `QUIT`. Clicking the status icon toggles the tray.
@MainActor
public final class ShelfMenuBarController: NSObject {
    private let statusItem: NSStatusItem
    private weak var panelController: ShelfPanelController?
    private let updateCoordinator: UpdateCoordinator
    private var inventoryObservation: AnyCancellable?

    public init(
        panelController: ShelfPanelController,
        updateCoordinator: UpdateCoordinator = UpdateCoordinator()
    ) {
        self.statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        self.panelController = panelController
        self.updateCoordinator = updateCoordinator
        super.init()

        if let button = statusItem.button {
            button.image = Self.statusIcon(isOccupied: !panelController.inventory.isEmpty)
            button.imageScaling = .scaleProportionallyDown
            button.target = self
            button.action = #selector(statusItemClicked(_:))
            button.sendAction(on: [.leftMouseUp, .rightMouseUp])
        }

        inventoryObservation = panelController.inventory.didChange.sink { [weak self] in
            self?.updateStatusIcon()
        }
    }

    private func updateStatusIcon() {
        statusItem.button?.image = Self.statusIcon(isOccupied: !(panelController?.inventory.isEmpty ?? true))
    }

    /// Draws a small, template-style pixel tray without a bitmap asset.
    /// The occupied form adds two stacked cards; the empty form leaves the
    /// tray visibly open while preserving the same monochrome silhouette.
    private static func statusIcon(isOccupied: Bool) -> NSImage {
        let iconSize = NSSize(width: 18, height: 18)
        let image = NSImage(size: iconSize)
        image.isTemplate = true
        image.accessibilityDescription = "ShotNDrop"
        image.lockFocus()
        defer { image.unlockFocus() }

        NSGraphicsContext.current?.imageInterpolation = .none
        NSColor.white.setFill()

        func pixel(_ x: CGFloat, _ y: CGFloat, _ width: CGFloat, _ height: CGFloat) {
            NSRect(x: x, y: y, width: width, height: height).fill()
        }

        // Open-top tray: chunky side walls, floor, and front lip.
        pixel(2, 3, 2, 9)
        pixel(14, 3, 2, 9)
        pixel(3, 2, 12, 2)
        pixel(4, 11, 10, 2)
        pixel(3, 4, 12, 2)

        if isOccupied {
            // Two offset cards make inventory presence legible at 1x.
            pixel(5, 8, 8, 5)
            pixel(4, 6, 10, 2)
            pixel(3, 5, 10, 2)
        } else {
            // A single inset floor mark keeps the empty state distinct.
            pixel(6, 6, 6, 1)
        }

        return image
    }

    @objc private func statusItemClicked(_ sender: NSStatusBarButton) {
        let event = NSApp.currentEvent
        if event?.type == .rightMouseUp {
            presentMenu()
        } else {
            guard let panelController else { return }
            if !panelController.panel.isVisible {
                panelController.show()
                return
            }
            // Left click toggles the expanded inventory.
            if panelController.isExpanded {
                panelController.collapse()
            } else {
                panelController.expand()
            }
        }
    }

    private func presentMenu() {
        let menu = NSMenu()
        let visibilityTitle = panelController?.panel.isVisible == true ? "Hide" : "Show"
        let visibility = NSMenuItem(
            title: visibilityTitle,
            action: #selector(toggleVisibility),
            keyEquivalent: ""
        )
        visibility.image = NSImage(
            systemSymbolName: visibilityTitle == "Hide" ? "eye.slash" : "eye",
            accessibilityDescription: visibilityTitle
        )
        visibility.target = self
        menu.addItem(visibility)

        let clear = NSMenuItem(title: "Clear", action: #selector(clear), keyEquivalent: "")
        clear.image = NSImage(systemSymbolName: "trash", accessibilityDescription: "Clear")
        clear.target = self
        clear.isEnabled = !(panelController?.inventory.isEmpty ?? true)
        menu.addItem(clear)
        let checkForUpdates = NSMenuItem(
            title: "Check for Updates",
            action: #selector(checkForUpdates),
            keyEquivalent: ""
        )
        checkForUpdates.image = NSImage(
            systemSymbolName: "arrow.clockwise",
            accessibilityDescription: "Check for Updates"
        )
        checkForUpdates.target = self
        menu.addItem(checkForUpdates)

        let quit = NSMenuItem(title: "Quit", action: #selector(quit), keyEquivalent: "q")
        quit.image = NSImage(systemSymbolName: "power", accessibilityDescription: "Quit")
        quit.target = self
        menu.addItem(quit)

        statusItem.menu = menu
        statusItem.button?.performClick(nil)
        statusItem.menu = nil
    }

    @objc private func checkForUpdates() {
        updateCoordinator.checkForUpdates(from: panelController?.panel)
    }

    @objc private func clear() {
        panelController?.inventory.clear()
        panelController?.sessionStore.clearContents()
        panelController?.renderSlot()
    }

    @objc private func toggleVisibility() {
        guard let panelController else { return }
        if panelController.panel.isVisible {
            panelController.hide()
        } else {
            panelController.show()
        }
    }

    @objc private func quit() {
        NSApp.terminate(nil)
    }

    // Introspection hooks used by tests.
    public var menuTitles: [String] {
        let visibilityTitle = panelController?.panel.isVisible == true ? "Hide" : "Show"
        return [visibilityTitle, "Clear", "Check for Updates", "Quit"]
    }
}
