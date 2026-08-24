import SwiftUI
import AppKit

@main
struct ShotNDropApp: App {
    @NSApplicationDelegateAdaptor(ShotNDropAppDelegate.self) var appDelegate

    var body: some Scene {
        Settings { EmptyView() }
    }
}

@MainActor
final class ShotNDropAppDelegate: NSObject, NSApplicationDelegate {
    private var sessionStore: ShelfSessionStore?
    private var inventory: ShelfInventory?
    private var panelController: ShelfPanelController?
    private var menuBarController: ShelfMenuBarController?

    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.accessory)
        PixelDesign.Font.registerAll()

        do {
            let store = try ShelfSessionStore()
            let inventory = ShelfInventory()
            let panel = ShelfPanelController(inventory: inventory, sessionStore: store)
            let menu = ShelfMenuBarController(panelController: panel)

            self.sessionStore = store
            self.inventory = inventory
            self.panelController = panel
            self.menuBarController = menu

            panel.showAtDefaultPosition()
        } catch {
            NSLog("ShotNDrop failed to launch: \(error)")
        }
    }

    func applicationWillTerminate(_ notification: Notification) {
        panelController?.inventory.clear()
        sessionStore?.shutdown()
    }
}
