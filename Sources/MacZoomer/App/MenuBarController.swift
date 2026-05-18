import AppKit
import Combine

@MainActor
final class MenuBarController {
    private let statusItem: NSStatusItem
    private let preferences: Preferences
    private let permissions: PermissionCoordinator
    private let hotkeys: HotkeyManager
    private let openSettings: () -> Void

    private var cancellables = Set<AnyCancellable>()

    init(
        preferences: Preferences,
        permissions: PermissionCoordinator,
        hotkeys: HotkeyManager,
        openSettings: @escaping () -> Void
    ) {
        self.preferences = preferences
        self.permissions = permissions
        self.hotkeys = hotkeys
        self.openSettings = openSettings
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

    @objc private func triggerZoom()      { notImplemented("Zoom") }
    @objc private func triggerLiveZoom()  { notImplemented("Live Zoom") }
    @objc private func triggerDraw()      { notImplemented("Draw") }
    @objc private func triggerBreak()     { notImplemented("Break Timer") }
    @objc private func triggerRecord()    { notImplemented("Record") }

    private func notImplemented(_ feature: String) {
        let alert = NSAlert()
        alert.messageText = "\(feature) is not implemented yet"
        alert.informativeText = "MacZoomer is in Phase 0 (Foundations). This feature will ship in a later phase."
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
