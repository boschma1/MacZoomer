import AppKit
import SwiftUI

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    let preferences = Preferences.shared
    let permissions = PermissionCoordinator()
    lazy var hotkeys = HotkeyManager(preferences: preferences)
    lazy var zoomMode = ZoomMode(preferences: preferences, permissions: permissions)

    private var menuBarController: MenuBarController?

    nonisolated override init() {
        super.init()
    }

    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.accessory)

        menuBarController = MenuBarController(
            preferences: preferences,
            permissions: permissions,
            hotkeys: hotkeys,
            zoomMode: zoomMode,
            openSettings: { [weak self] in self?.openSettings() }
        )

        permissions.refreshAll()
        hotkeys.setHandler { [weak self] action in
            self?.dispatch(action: action)
        }
        hotkeys.registerAll()
    }

    func applicationWillTerminate(_ notification: Notification) {
        hotkeys.unregisterAll()
    }

    private func dispatch(action: HotkeyAction) {
        switch action {
        case .zoom:
            if zoomMode.isActive {
                zoomMode.deactivate()
            } else {
                zoomMode.activate()
            }
        default:
            // Other actions land in later phases.
            break
        }
    }

    private func openSettings() {
        NSApp.activate(ignoringOtherApps: true)
        let modern = Selector(("showSettingsWindow:"))
        if NSApp.responds(to: modern) {
            NSApp.sendAction(modern, to: nil, from: nil)
            return
        }
        NSApp.sendAction(Selector(("showPreferencesWindow:")), to: nil, from: nil)
    }
}
