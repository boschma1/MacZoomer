import AppKit
import Sparkle

/// Thin wrapper around `SPUStandardUpdaterController` so the rest of the app
/// only depends on AppKit. The controller is created with
/// `startingUpdater: true`, which automatically schedules background checks
/// according to the `SUEnableAutomaticChecks` / `SUScheduledCheckInterval`
/// keys in `Info.plist`.
@MainActor
final class UpdaterController {
    private let standardController: SPUStandardUpdaterController

    init() {
        self.standardController = SPUStandardUpdaterController(
            startingUpdater: true,
            updaterDelegate: nil,
            userDriverDelegate: nil
        )
    }

    /// Whether the user can currently trigger an update check (Sparkle is
    /// briefly busy right after launch / during a check).
    var canCheckForUpdates: Bool {
        standardController.updater.canCheckForUpdates
    }

    /// The target/selector pair to wire into an `NSMenuItem` so the
    /// standard "Check for Updates…" item works without going through the
    /// responder chain.
    func menuTarget() -> AnyObject {
        standardController
    }

    func menuAction() -> Selector {
        #selector(SPUStandardUpdaterController.checkForUpdates(_:))
    }
}
