import AppKit
import CoreGraphics
import ScreenCaptureKit
import UniformTypeIdentifiers

/// Coordinates the four screenshot actions:
/// 1. Copy full screen to clipboard
/// 2. Copy region to clipboard
/// 3. Save full screen as PNG
/// 4. Save region as PNG
///
/// Captures via `SCScreenshotManager` with our own app's windows excluded,
/// so any active overlays (zoom views, region selector dim) never end up in
/// the saved image. Files are written to the user-configured screenshot
/// folder (default: `~/Desktop`).
@MainActor
public final class ScreenshotMode: NSObject {
    private let preferences: Preferences
    private let permissions: PermissionCoordinator
    private let regionSelector = RegionSelector()

    private var hasTriggeredSystemPermissionPrompt = false
    private var isShowingPermissionAlert = false

    public init(preferences: Preferences, permissions: PermissionCoordinator) {
        self.preferences = preferences
        self.permissions = permissions
        super.init()
    }

    // MARK: - Public actions

    public func copyFullScreenToClipboard() {
        guard ensurePermission() else { return }
        Task { @MainActor in
            guard let (image, _) = await captureScreenAtCursor(excludeOurApp: true) else {
                ScreenshotHUD.shared.show(.failed("Capture failed"))
                return
            }
            ClipboardWriter.write(cgImage: image)
            ScreenshotHUD.shared.show(.copied)
        }
    }

    public func saveFullScreenToFile() {
        guard ensurePermission() else { return }
        Task { @MainActor in
            guard let (image, _) = await captureScreenAtCursor(excludeOurApp: true) else {
                ScreenshotHUD.shared.show(.failed("Capture failed"))
                return
            }
            do {
                let url = try ImageFileWriter.writePNG(
                    image: image,
                    folder: preferences.screenshotFolder
                )
                ScreenshotHUD.shared.show(.saved(url))
            } catch {
                ScreenshotHUD.shared.show(.failed("Save failed: \(error.localizedDescription)"))
            }
        }
    }

    public func copyRegionToClipboard() {
        guard ensurePermission() else { return }
        captureRegion { image in
            guard let image else { return }
            ClipboardWriter.write(cgImage: image)
            ScreenshotHUD.shared.show(.copied)
        }
    }

    public func saveRegionToFile() {
        guard ensurePermission() else { return }
        captureRegion { [weak self] image in
            guard let self else { return }
            guard let image else { return }
            do {
                let url = try ImageFileWriter.writePNG(
                    image: image,
                    folder: self.preferences.screenshotFolder
                )
                ScreenshotHUD.shared.show(.saved(url))
            } catch {
                ScreenshotHUD.shared.show(.failed("Save failed: \(error.localizedDescription)"))
            }
        }
    }

    // MARK: - Region capture pipeline

    private func captureRegion(completion: @escaping (CGImage?) -> Void) {
        guard !regionSelector.isActive else {
            completion(nil)
            return
        }
        regionSelector.present { [weak self] selection in
            guard let self else { completion(nil); return }
            guard let selection else { completion(nil); return }

            // The selector windows are already torn down by `present`'s
            // completion contract, but give the WindowServer one runloop
            // tick to actually composite without them before we capture.
            DispatchQueue.main.async {
                Task { @MainActor in
                    let image = await self.captureRegionImage(selection: selection)
                    completion(image)
                }
            }
        }
    }

    private func captureRegionImage(selection: RegionSelection) async -> CGImage? {
        guard let display = await scDisplay(matching: selection.screenDisplayID) else {
            return nil
        }
        let ownApps = await ownAppsFromContent()

        // Use SCStreamConfiguration.sourceRect to crop server-side in pixel
        // coords. The source rect uses the display's top-left origin coord
        // system in *points* (not pixels), per Apple's docs — the stream
        // multiplies by display.scale internally.
        let pointHeight = selection.screenFrame.height
        let sourceRect = CGRect(
            x: selection.screenLocalRect.origin.x,
            y: pointHeight - selection.screenLocalRect.origin.y - selection.screenLocalRect.height,
            width: selection.screenLocalRect.width,
            height: selection.screenLocalRect.height
        )

        let filter = SCContentFilter(
            display: display,
            excludingApplications: ownApps,
            exceptingWindows: []
        )
        let config = SCStreamConfiguration()
        config.sourceRect = sourceRect
        config.width = Int(selection.screenLocalRect.width * selection.backingScale)
        config.height = Int(selection.screenLocalRect.height * selection.backingScale)
        config.showsCursor = false

        do {
            let image = try await SCScreenshotManager.captureImage(
                contentFilter: filter,
                configuration: config
            )
            return image
        } catch {
            NSLog("MacZoomer: region capture failed: \(error)")
            return nil
        }
    }

    // MARK: - Full screen capture

    private func captureScreenAtCursor(excludeOurApp: Bool) async -> (CGImage, NSScreen)? {
        let cursor = NSEvent.mouseLocation
        let target = NSScreen.screens.first(where: { $0.frame.contains(cursor) })
                     ?? NSScreen.main
                     ?? NSScreen.screens.first
        guard let screen = target, let displayID = screen.displayID else { return nil }
        guard let scDisplay = await scDisplay(matching: displayID) else { return nil }

        let ownApps = excludeOurApp ? await ownAppsFromContent() : []
        let filter = SCContentFilter(
            display: scDisplay,
            excludingApplications: ownApps,
            exceptingWindows: []
        )
        let config = SCStreamConfiguration()
        config.width = Int(scDisplay.width)
        config.height = Int(scDisplay.height)
        config.showsCursor = false

        do {
            let image = try await SCScreenshotManager.captureImage(
                contentFilter: filter,
                configuration: config
            )
            return (image, screen)
        } catch {
            NSLog("MacZoomer: full screen capture failed: \(error)")
            return nil
        }
    }

    private func scDisplay(matching displayID: CGDirectDisplayID) async -> SCDisplay? {
        do {
            let content = try await SCShareableContent.excludingDesktopWindows(
                false,
                onScreenWindowsOnly: true
            )
            return content.displays.first(where: { $0.displayID == displayID })
        } catch {
            return nil
        }
    }

    private func ownAppsFromContent() async -> [SCRunningApplication] {
        do {
            let content = try await SCShareableContent.excludingDesktopWindows(
                false,
                onScreenWindowsOnly: true
            )
            let ownPID = ProcessInfo.processInfo.processIdentifier
            return content.applications.filter { $0.processID == ownPID }
        } catch {
            return []
        }
    }

    // MARK: - Permission gating

    private func ensurePermission() -> Bool {
        if CGPreflightScreenCaptureAccess() { return true }
        handlePermissionDenied()
        return false
    }

    private func handlePermissionDenied() {
        // On the very first denial, just trigger the system Screen
        // Recording prompt and let the user respond to it. Stacking our
        // own alert on top simultaneously was confusing (two dialogs at
        // once, both about the same thing). If permission is *still* not
        // granted on a later hotkey press, we'll surface our alert with
        // explicit Settings deep-link guidance.
        if !hasTriggeredSystemPermissionPrompt {
            hasTriggeredSystemPermissionPrompt = true
            permissions.requestIfNeeded(.screenRecording)
            return
        }
        presentPermissionAlert()
    }

    private func presentPermissionAlert() {
        guard !isShowingPermissionAlert else { return }
        isShowingPermissionAlert = true
        defer { isShowingPermissionAlert = false }

        let alert = NSAlert()
        alert.messageText = "Screen Recording permission needed"
        alert.informativeText = """
            MacZoomer can't take screenshots until Screen Recording is enabled in System Settings.

            After enabling it, please quit MacZoomer from the menu bar and relaunch — macOS only applies a new Screen Recording grant when the app is freshly launched.
            """
        alert.addButton(withTitle: "Open System Settings")
        alert.addButton(withTitle: "Cancel")
        if alert.runModal() == .alertFirstButtonReturn {
            permissions.openSettings(for: .screenRecording)
        }
    }
}
