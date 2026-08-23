import SwiftUI
import AppKit

@main
struct ShotNDropApp: App {
    @StateObject private var coordinator = AppCoordinator()

    var body: some Scene {
        MenuBarExtra("ShotNDrop", systemImage: "photo.on.rectangle.angled") {
            Button(coordinator.folderMenuTitle, action: coordinator.chooseFolder)
            Divider()
            Button("Reopen Overlay", action: coordinator.reopenOverlay)
                .disabled(coordinator.queue.isEmpty)
            Button("Restore Last Closed", action: coordinator.restoreLastClosed)
                .disabled(coordinator.queue.lastClosed == nil)
            Button("Clear Queue", action: coordinator.clearQueue)
                .disabled(coordinator.queue.isEmpty)
            Divider()
            Button("Quit ShotNDrop") {
                coordinator.shutdown()
                NSApp.terminate(nil)
            }.keyboardShortcut("q")
        }
    }
}

@MainActor
final class AppCoordinator: ObservableObject {
    let queue = ScreenshotQueue()
    let folderAccess = WatchedFolderAccess()
    let overlay = OverlayPanelController()

    @Published private(set) var currentFolder: URL?

    private var watcher: ScreenshotWatcher?

    var folderMenuTitle: String {
        if let folder = currentFolder {
            return "Watching \(folder.lastPathComponent)…"
        }
        return "Choose Screenshot Folder…"
    }

    init() {
        overlay.onClose = { [weak self] item in
            self?.close(item)
        }
        // Best-effort restore on launch.
        do {
            let url = try folderAccess.restoreFromBookmark()
            self.currentFolder = url
            startWatching(folder: url)
        } catch {
            // Silent: user will pick a folder from the menu.
        }
    }

    private func close(_ item: ScreenshotItem) {
        _ = queue.close(id: item.id)
        if queue.isEmpty {
            overlay.hide()
        } else {
            overlay.show(items: queue.items)
        }
    }

    func chooseFolder() {
        do {
            let url = try folderAccess.promptForFolder()
            self.currentFolder = url
            startWatching(folder: url)
        } catch {
            // User cancelled or access denied — leave state unchanged.
        }
    }

    func reopenOverlay() {
        overlay.show(items: queue.items)
    }

    func restoreLastClosed() {
        let outcome = queue.restoreLastClosed(now: Date()) { item in
            (try? item.url.checkResourceIsReachable()) == true
        }
        switch outcome {
        case .restored, .evictedForRestore:
            overlay.show(items: queue.items)
        case .none, .expired, .unavailable:
            break
        }
    }

    func clearQueue() {
        queue.clear()
        overlay.hide()
    }

    func shutdown() {
        // Order: stop producer (watcher), tear down UI, drop transient state,
        // release scoped access last so nothing in flight still needs it.
        watcher?.stop()
        watcher = nil
        overlay.tearDown()
        queue.clear()
        ThumbnailCache.shared.purge()
        folderAccess.stopScopedAccess()
    }

    private func startWatching(folder: URL) {
        watcher?.stop()
        let w = ScreenshotWatcher(
            onAccepted: { [weak self] items in
                guard let self else { return }
                var didInsert = false
                for item in items {
                    switch self.queue.insert(item) {
                    case .duplicate:
                        continue
                    case .inserted, .overflowEvicted:
                        didInsert = true
                    }
                }
                if didInsert {
                    self.overlay.show(items: self.queue.items)
                }
            },
            onStopped: { [weak self] _ in
                self?.watcher = nil
                self?.currentFolder = nil
            }
        )
        self.watcher = w
        w.start(folder: folder)
    }
}
