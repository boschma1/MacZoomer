import AppKit
import SwiftUI

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    let preferences = Preferences.shared
    let permissions = PermissionCoordinator()
    lazy var hotkeys = HotkeyManager(preferences: preferences)
    lazy var zoomMode = ZoomMode(preferences: preferences, permissions: permissions)
    lazy var liveZoomMode = LiveZoomMode(preferences: preferences, permissions: permissions)
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
            liveZoomMode: liveZoomMode,
            drawingMode: drawingMode,
            breakTimerMode: breakTimerMode,
            openSettings: { [weak self] in self?.openSettings() },
            dispatchAction: { [weak self] action in self?.dispatch(action: action) }
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
                if liveZoomMode.isActive { liveZoomMode.deactivateImmediately() }
                zoomMode.activate()
            }
        case .liveZoom:
            if liveZoomMode.isActive {
                liveZoomMode.deactivate()
            } else {
                if zoomMode.isActive { zoomMode.deactivateImmediately() }
                liveZoomMode.activate()
            }
        case .draw, .liveDraw:
            if drawingMode.isActive {
                drawingMode.deactivate()
            } else if zoomMode.isActive {
                // Zoom→Draw composition: hand the current zoomed view over to
                // Draw as a frozen background so annotations land on top of
                // exactly what the user is looking at.
                let images = zoomMode.currentDisplayedImages()
                zoomMode.deactivateImmediately()
                if images.isEmpty {
                    drawingMode.activate()
                } else {
                    drawingMode.activate(frozenImages: images)
                }
            } else if liveZoomMode.isActive {
                // Live Zoom → Draw: stop the stream and freeze the current
                // displayed live frame as the draw background.
                liveZoomMode.deactivateImmediately()
                drawingMode.activate()
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
