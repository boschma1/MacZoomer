import AppKit
import SwiftUI

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    let preferences = Preferences.shared
    let permissions = PermissionCoordinator()
    lazy var hotkeys = HotkeyManager(preferences: preferences)
    lazy var zoomMode = ZoomMode(preferences: preferences, permissions: permissions)
    lazy var drawingMode = DrawingMode()
    lazy var breakTimerMode = BreakTimerMode(preferences: preferences)

    private var menuBarController: MenuBarController?
    private var settingsWindowController: SettingsWindowController?
    private var settingsObserver: NSObjectProtocol?

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
            drawingMode: drawingMode,
            breakTimerMode: breakTimerMode,
            openSettings: { [weak self] in self?.openSettings() }
        )

        permissions.refreshAll()
        hotkeys.setHandler { [weak self] action in
            self?.dispatch(action: action)
        }
        hotkeys.registerAll()

        settingsObserver = NotificationCenter.default.addObserver(
            forName: NSWindow.willCloseNotification,
            object: nil,
            queue: .main
        ) { notification in
            MainActor.assumeIsolated {
                guard let window = notification.object as? NSWindow,
                      Self.isSettingsWindow(window) else { return }
                DispatchQueue.main.async {
                    let hasTitledWindow = NSApp.windows.contains { other in
                        other !== window && other.isVisible && other.styleMask.contains(.titled)
                    }
                    if !hasTitledWindow {
                        NSApp.setActivationPolicy(.accessory)
                    }
                }
            }
        }
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
        case .draw, .liveDraw:
            if drawingMode.isActive {
                drawingMode.deactivate()
            } else {
                drawingMode.activate()
            }
        case .breakTimer:
            if breakTimerMode.isActive {
                breakTimerMode.deactivate()
            } else {
                breakTimerMode.activate()
            }
        default:
            // Other actions land in later phases.
            break
        }
    }

    private func openSettings() {
        // Build the window lazily so dependencies finish initializing first.
        if settingsWindowController == nil {
            settingsWindowController = SettingsWindowController(
                preferences: preferences,
                permissions: permissions,
                hotkeys: hotkeys
            )
        }

        // Switch to `.regular` so the window can take focus from a menu-bar
        // app. We flip back to `.accessory` once the window closes.
        NSApp.setActivationPolicy(.regular)
        NSApp.activate(ignoringOtherApps: true)
        settingsWindowController?.show()
    }

    private static func isSettingsWindow(_ window: NSWindow) -> Bool {
        let title = window.title.lowercased()
        if title.contains("settings") || title.contains("preferences") { return true }
        if let identifier = window.identifier?.rawValue.lowercased(),
           identifier.contains("settings") || identifier.contains("preferences") {
            return true
        }
        return false
    }
}
