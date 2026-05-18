import Foundation
import ServiceManagement

/// Thin wrapper around `SMAppService.mainApp` so the rest of the app
/// doesn't import ServiceManagement directly. Reading ``isEnabled`` is
/// cheap (a status enum lookup), so we don't cache it — the UI just
/// re-reads it whenever it needs the current truth.
///
/// macOS 13+ only. The deployment target is 14.0 so the availability
/// check is omitted.
@MainActor
enum LaunchAtLogin {
    /// Current registration state read directly from the system. Reflects
    /// any changes the user made in System Settings → General → Login
    /// Items, not just toggles inside MacZoomer.
    static var isEnabled: Bool {
        SMAppService.mainApp.status == .enabled
    }

    /// Toggle the registration. Throws if the system refused (most
    /// commonly because the bundle isn't in `/Applications` or its code
    /// signature changed between launches).
    static func set(_ enabled: Bool) throws {
        let service = SMAppService.mainApp
        switch (enabled, service.status) {
        case (true, .enabled):
            return
        case (false, .notRegistered), (false, .notFound):
            return
        case (true, _):
            try service.register()
        case (false, _):
            try service.unregister()
        }
    }
}
