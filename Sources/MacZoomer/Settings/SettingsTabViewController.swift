import AppKit
import SwiftUI

/// Classic Preferences-style tab bar: icon-over-label toolbar items at the
/// top, content panes below. Uses AppKit's `NSTabViewController` in
/// `.toolbar` style because SwiftUI's `TabView` renders as the modern
/// "segmented navigation" pill on macOS 14+ and isn't customizable to the
/// classic look.
@MainActor
final class SettingsTabViewController: NSTabViewController {
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
        super.init(nibName: nil, bundle: nil)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) is not supported")
    }

    override func viewDidLoad() {
        super.viewDidLoad()
        tabStyle = .toolbar
        canPropagateSelectedChildViewControllerTitle = false

        addTab(
            label: "General",
            image: NSImage(systemSymbolName: "gear", accessibilityDescription: "General")!,
            view: GeneralSettingsView()
        )
        addTab(
            label: "Break Timer",
            image: NSImage(systemSymbolName: "timer", accessibilityDescription: "Break Timer")!,
            view: BreakTimerSettingsView()
        )
        addTab(
            label: "Hotkeys",
            image: NSImage(systemSymbolName: "keyboard", accessibilityDescription: "Hotkeys")!,
            view: HotkeysSettingsView()
        )
        addTab(
            label: "Permissions",
            image: NSImage(systemSymbolName: "lock.shield", accessibilityDescription: "Permissions")!,
            view: PermissionsSettingsView()
        )
        addTab(
            label: "About",
            image: NSImage(systemSymbolName: "info.circle", accessibilityDescription: "About")!,
            view: AboutSettingsView()
        )
    }

    private func addTab<Content: View>(label: String, image: NSImage, view: Content) {
        let wrapped = view
            .environmentObject(preferences)
            .environmentObject(permissions)
            .environmentObject(hotkeys)
        let host = NSHostingController(rootView: wrapped)
        host.title = label
        host.preferredContentSize = NSSize(width: 560, height: 420)

        let item = NSTabViewItem(viewController: host)
        item.label = label
        item.image = image
        addTabViewItem(item)
    }
}
