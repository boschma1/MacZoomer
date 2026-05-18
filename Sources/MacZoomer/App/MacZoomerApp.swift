import AppKit
import SwiftUI

@main
struct MacZoomerApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate

    var body: some Scene {
        // Required by the `App` protocol; we never actually open this scene.
        // The real settings window is presented by `SettingsWindowController`,
        // and the rest of the UI is menu-bar + transient overlays.
        Settings { EmptyView() }
    }
}
