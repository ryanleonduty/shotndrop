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
    private let updateCoordinator = UpdateCoordinator()

    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.accessory)
        PixelDesign.Font.registerAll()

        do {
            let store = try ShelfSessionStore()
            let inventory = ShelfInventory()
            let panel = ShelfPanelController(
                inventory: inventory,
                sessionStore: store,
                updateCoordinator: updateCoordinator
            )
            let menu = ShelfMenuBarController(
                panelController: panel,
                updateCoordinator: updateCoordinator
            )

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
