import Observation
import Sparkle

/// Updates via Sparkle: once a day it reads the appcast on the newest GitHub release (no tokens, no system profile),
/// downloads a newer build in the background, checks its signature, and swaps it in while the app is idle.
@MainActor @Observable
final class Updater: NSObject, SPUUpdaterDelegate, SPUStandardUserDriverDelegate {
    static let shared = Updater()

    @ObservationIgnored private var controller: SPUStandardUpdaterController!
    @ObservationIgnored private weak var store: Store?

    /// One switch for checking and installing; Sparkle keeps both in its own defaults.
    var automatic = false {
        didSet {
            controller.updater.automaticallyChecksForUpdates = automatic
            controller.updater.automaticallyDownloadsUpdates = automatic
        }
    }

    var canCheck: Bool { controller.updater.canCheckForUpdates }

    func start(store: Store) {
        self.store = store
        #if DEBUG
        let start = false // a dev build would otherwise replace itself with the latest release
        #else
        let start = true
        #endif
        controller = SPUStandardUpdaterController(startingUpdater: start, updaterDelegate: self, userDriverDelegate: self)
        automatic = controller.updater.automaticallyChecksForUpdates && controller.updater.automaticallyDownloadsUpdates
    }

    func checkNow() {
        controller.checkForUpdates(nil)
    }

    /// A menu bar app rarely quits, so "install on quit" could wait for weeks. Install now instead, once the menu
    /// is closed and nothing is building; Sparkle relaunches the new version a second later.
    nonisolated func updater(_ updater: SPUUpdater, willInstallUpdateOnQuit item: SUAppcastItem,
                             immediateInstallationBlock: @escaping () -> Void) -> Bool {
        nonisolated(unsafe) let install = immediateInstallationBlock
        Task { @MainActor in
            while let store, store.menuOpen || store.anyBuilding {
                try? await Task.sleep(for: .seconds(60))
            }
            install()
        }
        return true
    }

    /// Background app: show any update window without stealing focus (Sparkle's advice for menu bar apps).
    nonisolated var supportsGentleScheduledUpdateReminders: Bool { true }
}
