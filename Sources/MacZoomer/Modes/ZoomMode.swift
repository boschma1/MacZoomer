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

    /// We call `CGRequestScreenCaptureAccess()` at most once per process to
    /// register a TCC entry and trigger the system permission prompt.
    /// Subsequent denials just route the user back to our friendly alert,
    /// which is a much better experience than the system dialog reappearing
    /// on every hotkey press.
    private var hasTriggeredSystemPermissionPrompt = false

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
                handlePermissionDenied()
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

    /// Tear down the zoom overlay immediately (no animation). Used by the
    /// Zoom→Draw handoff which closes the zoom windows synchronously before
    /// activating draw mode with their final visible state.
    public func deactivateImmediately() {
        guard isActive else { return }
        isActive = false
        for window in windows {
            window.orderOut(nil)
        }
        windows.removeAll()
        NSCursor.unhide()
    }

    /// Render every active zoom window's current view to a CGImage. The result
    /// is one `DisplayCapture` per display, suitable for handing to
    /// ``DrawingMode/activate(frozenImages:)`` so the user can annotate on
    /// top of the zoomed image.
    public func currentDisplayedImages() -> [DisplayCapture] {
        var results: [DisplayCapture] = []
        for window in windows {
            guard let image = window.zoomView.renderCurrentView() else { continue }
            guard let screen = window.screen ?? NSScreen.main else { continue }
            let displayID = screen.displayID ?? CGMainDisplayID()
            results.append(DisplayCapture(
                screen: screen,
                displayID: displayID,
                image: image,
                backingScale: screen.backingScaleFactor
            ))
        }
        return results
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

    private func handlePermissionDenied() {
        // The first time we see "denied", trigger the system prompt so a TCC
        // entry is registered for the app (otherwise the user has nothing to
        // toggle in System Settings → Privacy & Security → Screen Recording).
        // On subsequent denials we just show our own alert.
        if !hasTriggeredSystemPermissionPrompt {
            hasTriggeredSystemPermissionPrompt = true
            permissions.requestIfNeeded(.screenRecording)
        }
        presentPermissionAlert()
    }

    private func presentPermissionAlert() {
        let alert = NSAlert()
        alert.messageText = "Screen Recording permission needed"
        alert.informativeText = """
            MacZoomer can't capture the screen for Zoom Mode until Screen Recording is enabled in System Settings.

            After enabling it, please quit MacZoomer and relaunch — macOS only applies the new permission at process start.
            """
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
