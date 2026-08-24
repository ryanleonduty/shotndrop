import AppKit

/// Owns the menu-bar `NSStatusItem` and its three-item menu:
/// `SHOW SHELF`, `CLEAR`, `QUIT`. Clicking the status icon toggles the tray.
@MainActor
public final class ShelfMenuBarController: NSObject {
    private let statusItem: NSStatusItem
    private weak var panelController: ShelfPanelController?

    public init(panelController: ShelfPanelController) {
        self.statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        self.panelController = panelController
        super.init()

        if let button = statusItem.button {
            button.image = NSImage(systemSymbolName: "photo.on.rectangle.angled", accessibilityDescription: "ShotNDrop")
            button.target = self
            button.action = #selector(statusItemClicked(_:))
            button.sendAction(on: [.leftMouseUp, .rightMouseUp])
        }
    }

    @objc private func statusItemClicked(_ sender: NSStatusBarButton) {
        let event = NSApp.currentEvent
        if event?.type == .rightMouseUp {
            presentMenu()
        } else {
            // Left click toggles the expanded inventory.
            guard let panelController else { return }
            if panelController.isExpanded {
                panelController.collapse()
            } else {
                panelController.expand()
            }
        }
    }

    private func presentMenu() {
        let menu = NSMenu()
        let show = NSMenuItem(title: "SHOW SHELF", action: #selector(showShelf), keyEquivalent: "")
        show.target = self
        menu.addItem(show)
        let clear = NSMenuItem(title: "CLEAR", action: #selector(clear), keyEquivalent: "")
        clear.target = self
        clear.isEnabled = !(panelController?.inventory.isEmpty ?? true)
        menu.addItem(clear)
        let quit = NSMenuItem(title: "QUIT", action: #selector(quit), keyEquivalent: "q")
        quit.target = self
        menu.addItem(quit)

        statusItem.menu = menu
        statusItem.button?.performClick(nil)
        statusItem.menu = nil
    }

    @objc private func showShelf() {
        panelController?.showAtDefaultPosition()
    }

    @objc private func clear() {
        panelController?.inventory.clear()
        panelController?.sessionStore.clearContents()
        panelController?.renderSlot()
    }

    @objc private func quit() {
        NSApp.terminate(nil)
    }

    // Introspection hooks used by tests.
    public var menuTitles: [String] { ["SHOW SHELF", "CLEAR", "QUIT"] }
}
