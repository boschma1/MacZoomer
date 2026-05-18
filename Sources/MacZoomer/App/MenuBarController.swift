import AppKit
import Combine

@MainActor
final class MenuBarController {
    private let statusItem: NSStatusItem
    private let preferences: Preferences
    private let permissions: PermissionCoordinator
    private let hotkeys: HotkeyManager
    private let zoomMode: ZoomMode
    private let liveZoomMode: LiveZoomMode
    private let drawingMode: DrawingMode
    private let breakTimerMode: BreakTimerMode
    private let openSettings: () -> Void
    private let dispatchAction: (HotkeyAction) -> Void

    private var cancellables = Set<AnyCancellable>()

    init(
        preferences: Preferences,
        permissions: PermissionCoordinator,
        hotkeys: HotkeyManager,
        zoomMode: ZoomMode,
        liveZoomMode: LiveZoomMode,
        drawingMode: DrawingMode,
        breakTimerMode: BreakTimerMode,
        openSettings: @escaping () -> Void,
        dispatchAction: @escaping (HotkeyAction) -> Void
    ) {
        self.preferences = preferences
        self.permissions = permissions
        self.hotkeys = hotkeys
        self.zoomMode = zoomMode
        self.liveZoomMode = liveZoomMode
        self.drawingMode = drawingMode
        self.breakTimerMode = breakTimerMode
        self.openSettings = openSettings
        self.dispatchAction = dispatchAction
        self.statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)

        configureButton()
        rebuildMenu()

        permissions.objectWillChange
            .receive(on: RunLoop.main)
            .sink { [weak self] _ in self?.rebuildMenu() }
            .store(in: &cancellables)
    }

    private func configureButton() {
        guard let button = statusItem.button else { return }
        let image = NSImage(
            systemSymbolName: "plus.magnifyingglass",
            accessibilityDescription: "MacZoomer"
        )
        image?.isTemplate = true
        button.image = image
        button.toolTip = "MacZoomer — screen zoom, drawing & screenshots"
        button.setAccessibilityLabel("MacZoomer")
        button.setAccessibilityRoleDescription("Menu bar item")
    }

    private func rebuildMenu() {
        let menu = NSMenu()

        menu.addItem(makeItem(
            title: "Zoom",
            shortcut: preferences.binding(for: .zoom),
            action: #selector(triggerZoom)
        ))
        menu.addItem(makeItem(
            title: "Live Zoom",
            shortcut: preferences.binding(for: .liveZoom),
            action: #selector(triggerLiveZoom)
        ))
        menu.addItem(makeItem(
            title: "Draw",
            shortcut: preferences.binding(for: .draw),
            action: #selector(triggerDraw)
        ))
        menu.addItem(makeItem(
            title: "Break Timer",
            shortcut: preferences.binding(for: .breakTimer),
            action: #selector(triggerBreak)
        ))
        menu.addItem(makeItem(
            title: "Record",
            shortcut: preferences.binding(for: .record),
            action: #selector(triggerRecord)
        ))

        menu.addItem(.separator())

        menu.addItem(makeItem(
            title: "Copy Screenshot",
            shortcut: preferences.binding(for: .snapshotClipboard),
            action: #selector(triggerCopyScreenshot)
        ))
        menu.addItem(makeItem(
            title: "Copy Region",
            shortcut: preferences.binding(for: .snapshotRegionClipboard),
            action: #selector(triggerCopyRegion)
        ))
        menu.addItem(makeItem(
            title: "Save Screenshot…",
            shortcut: preferences.binding(for: .snapshotFile),
            action: #selector(triggerSaveScreenshot)
        ))
        menu.addItem(makeItem(
            title: "Save Region…",
            shortcut: preferences.binding(for: .snapshotRegionFile),
            action: #selector(triggerSaveRegion)
        ))

        menu.addItem(.separator())

        if !permissions.allGranted {
            let item = NSMenuItem(
                title: "⚠ Permissions needed…",
                action: #selector(openPermissions),
                keyEquivalent: ""
            )
            item.target = self
            menu.addItem(item)
            menu.addItem(.separator())
        }

        let prefs = NSMenuItem(
            title: "Settings…",
            action: #selector(openSettingsAction),
            keyEquivalent: ","
        )
        prefs.target = self
        menu.addItem(prefs)

        menu.addItem(.separator())

        let quit = NSMenuItem(
            title: "Quit MacZoomer",
            action: #selector(quitAction),
            keyEquivalent: "q"
        )
        quit.target = self
        menu.addItem(quit)

        statusItem.menu = menu
    }

    private func makeItem(title: String, shortcut: HotkeyBinding?, action: Selector) -> NSMenuItem {
        let item = NSMenuItem(
            title: title,
            action: action,
            keyEquivalent: shortcut?.menuKeyEquivalent ?? ""
        )
        item.keyEquivalentModifierMask = shortcut?.menuModifierMask ?? []
        item.target = self
        return item
    }

    // MARK: - Mode placeholders (real implementations land in later phases)

    @objc private func triggerZoom()      { dispatchAction(.zoom) }
    @objc private func triggerLiveZoom()  { dispatchAction(.liveZoom) }
    @objc private func triggerDraw()      { dispatchAction(.draw) }
    @objc private func triggerBreak()     { dispatchAction(.breakTimer) }
    @objc private func triggerRecord()    { notImplemented("Record") }
    @objc private func triggerCopyScreenshot() { dispatchAction(.snapshotClipboard) }
    @objc private func triggerCopyRegion()     { dispatchAction(.snapshotRegionClipboard) }
    @objc private func triggerSaveScreenshot() { dispatchAction(.snapshotFile) }
    @objc private func triggerSaveRegion()     { dispatchAction(.snapshotRegionFile) }

    private func notImplemented(_ feature: String) {
        let alert = NSAlert()
        alert.messageText = "\(feature) is not implemented yet"
        alert.informativeText = "This feature will ship in a later phase. See plan.md for the roadmap."
        alert.alertStyle = .informational
        alert.addButton(withTitle: "OK")
        alert.runModal()
    }

    @objc private func openSettingsAction() {
        openSettings()
    }

    @objc private func openPermissions() {
        openSettings()
    }

    @objc private func quitAction() {
        NSApp.terminate(nil)
    }
}
