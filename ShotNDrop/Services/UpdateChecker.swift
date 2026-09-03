import AppKit
import Sparkle

/// Owns the Sparkle updater and exposes the single entry point the menu-bar and
/// panel "Check for Updates" actions call. Sparkle performs the appcast check,
/// shows the up-to-date / update-available dialog (with release notes), and
/// downloads, installs, and relaunches the app. Update archives are validated
/// against the `SUPublicEDKey` embedded in Info.plist (EdDSA); the matching
/// private key lives only in the release machine's login Keychain.
@MainActor
public final class UpdateCoordinator: NSObject {
    private let updaterController: SPUStandardUpdaterController

    public override init() {
        // startingUpdater: false so unit tests can construct the owning
        // controllers without launching Sparkle's background checks. The app
        // delegate calls `startUpdater()` once at launch.
        updaterController = SPUStandardUpdaterController(
            startingUpdater: false,
            updaterDelegate: nil,
            userDriverDelegate: nil
        )
        super.init()
    }

    /// Begins Sparkle's scheduled background update checks. Call once at launch.
    func startUpdater() {
        updaterController.startUpdater()
    }

    /// Presents Sparkle's user-initiated update flow. Shows a result dialog even
    /// when the app is already up to date.
    func checkForUpdates() {
        updaterController.checkForUpdates(nil)
    }
}
