import AppKit
import SwiftUI

/// Hosts ``SettingsScene`` inside a regular NSWindow so it works reliably
/// from a menu-bar-only (`.accessory`) app on every macOS version. The
/// SwiftUI `Settings` scene's `showSettingsWindow:` action can no-op when
/// the app isn't `.regular`; managing the window ourselves avoids that
/// entire class of issues.
@MainActor
final class SettingsWindowController: NSWindowController {
    private let preferences: Preferences
    private let permissions: PermissionCoordinator
    private let hotkeys: HotkeyManager

    init(
        preferences: Preferences,
        permissions: PermissionCoordinator,
        hotkeys: HotkeyManager
    ) {
        self.preferences = preferences
        self.permissions = permissions
        self.hotkeys = hotkeys

        let tabController = SettingsTabViewController(
            preferences: preferences,
            permissions: permissions,
            hotkeys: hotkeys
        )

        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 560, height: 420),
            styleMask: [.titled, .closable, .miniaturizable],
            backing: .buffered,
            defer: false
        )
        window.title = "MacZoomer Settings"
        window.identifier = NSUserInterfaceItemIdentifier("MacZoomerSettings")
        window.contentViewController = tabController
        window.toolbarStyle = .preference
        window.isReleasedWhenClosed = false
        window.center()

        super.init(window: window)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) is not supported")
    }

    func show() {
        guard let window else { return }
        if !window.isVisible {
            window.center()
        }
        window.makeKeyAndOrderFront(nil)
        window.orderFrontRegardless()
    }
}
