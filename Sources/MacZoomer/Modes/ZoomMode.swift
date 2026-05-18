import AppKit
import Combine

/// Coordinates entering, running, and exiting Zoom Mode across all displays.
@MainActor
public final class ZoomMode: NSObject, ObservableObject, @MainActor ZoomWindowDelegate {
    private let preferences: Preferences
    private let permissions: PermissionCoordinator
    private let capturer = ScreenCapturer()

    private var windows: [ZoomWindow] = []
    private(set) var isActive = false

    public init(preferences: Preferences, permissions: PermissionCoordinator) {
        self.preferences = preferences
        self.permissions = permissions
        super.init()
    }

    public func activate() {
        guard !isActive else { return }
        isActive = true

        Task { @MainActor in
            do {
                let captures = try await capturer.captureAllDisplays()
                guard !captures.isEmpty else {
                    isActive = false
                    return
                }
                present(captures: captures)
            } catch ScreenCaptureError.permissionDenied {
                isActive = false
                permissions.requestIfNeeded(.screenRecording)
                presentPermissionAlert()
            } catch {
                isActive = false
                NSLog("MacZoomer: zoom capture failed: \(error)")
            }
        }
    }

    public func deactivate() {
        guard isActive else { return }
        isActive = false
        let windowsToClose = windows
        windows.removeAll()
        guard !windowsToClose.isEmpty else { return }

        let remaining = windowsToClose.count
        var done = 0
        for window in windowsToClose {
            window.zoomView.performZoomOutAnimation { [weak window] in
                window?.orderOut(nil)
                done += 1
                if done == remaining {
                    NSCursor.unhide()
                }
            }
        }
    }

    // MARK: - Presentation

    private func present(captures: [DisplayCapture]) {
        let initialZoom = preferences.zoomInitialMagnification
        let smoothing = preferences.zoomSmoothing
        let mouseLocationGlobal = NSEvent.mouseLocation

        for capture in captures {
            let window = ZoomWindow(screen: capture.screen)
            window.modeDelegate = self
            window.zoomView.smoothing = smoothing

            let screenFrame = capture.screen.frame
            // Convert the global cursor location into the window's local coords.
            // mouseLocation is in global screen coords (bottom-left origin).
            let local = NSPoint(
                x: mouseLocationGlobal.x - screenFrame.origin.x,
                y: mouseLocationGlobal.y - screenFrame.origin.y
            )
            // If the cursor isn't on this screen, center this display's view.
            let focal: NSPoint
            if screenFrame.contains(mouseLocationGlobal) {
                focal = local
            } else {
                focal = NSPoint(x: screenFrame.width / 2, y: screenFrame.height / 2)
            }

            window.zoomView.configure(
                image: capture.image,
                backingScale: capture.backingScale,
                initialZoom: CGFloat(initialZoom),
                focalScreen: focal
            )
            window.makeKeyAndOrderFront(nil as AnyObject?)
            window.makeFirstResponder(window)
            windows.append(window)

            if preferences.zoomAnimate {
                window.zoomView.performZoomInAnimation()
            }
        }

        NSCursor.hide()
    }

    private func presentPermissionAlert() {
        let alert = NSAlert()
        alert.messageText = "Screen Recording permission needed"
        alert.informativeText = "MacZoomer can't capture the screen for Zoom Mode until Screen Recording is enabled in System Settings."
        alert.addButton(withTitle: "Open System Settings")
        alert.addButton(withTitle: "Cancel")
        if alert.runModal() == .alertFirstButtonReturn {
            permissions.openSettings(for: .screenRecording)
        }
    }

    // MARK: - ZoomWindowDelegate

    func zoomWindowDidRequestExit(_ window: ZoomWindow) {
        deactivate()
    }
}
