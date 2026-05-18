import AppKit
import SwiftUI

@main
struct MacZoomerApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate

    var body: some Scene {
        Settings {
            SettingsScene()
                .environmentObject(appDelegate.preferences)
                .environmentObject(appDelegate.permissions)
                .environmentObject(appDelegate.hotkeys)
        }
    }
}
