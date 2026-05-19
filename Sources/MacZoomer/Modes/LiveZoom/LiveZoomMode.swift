import AppKit
import CoreMedia
import ScreenCaptureKit

/// Coordinates entering, running, and exiting Live Zoom Mode across all displays.
///
/// Unlike `ZoomMode`, which captures a single still frame and pans/zooms over
/// that frozen image, `LiveZoomMode` runs an `SCStream` per display and feeds
/// frames to its `LiveZoomView`s in real time. The cursor's screen position
/// drives the focal point so panning works identically to static zoom.
@MainActor
public final class LiveZoomMode: NSObject, ObservableObject, @MainActor LiveZoomWindowDelegate {
    private let preferences: Preferences
    private let permissions: PermissionCoordinator

    private struct DisplayContext {
        let window: LiveZoomWindow
        let capturer: LiveScreenCapturer
        let display: SCDisplay
    }
    private var contexts: [DisplayContext] = []
    private(set) var isActive = false

    /// 60 Hz timer that polls the global cursor position and routes it to
    /// each live-zoom view's focal-screen update. We poll instead of relying
    /// on `NSWindow.mouseMoved` because under `.accessory` activation policy
    /// + SCStream's WindowServer hooks the borderless screen-saver-level
    /// window doesn't reliably receive mouse-moved events. Polling is
    /// equivalent at frame cadence and bypasses the event-delivery quirk
    /// entirely.
    private var cursorTimer: Timer?
    private var lastCursorLocation: NSPoint = .zero

    private var hasTriggeredSystemPermissionPrompt = false
    private var isShowingPermissionAlert = false

    public init(preferences: Preferences, permissions: PermissionCoordinator) {
        self.preferences = preferences
        self.permissions = permissions
        super.init()
    }

    public func activate() {
        guard !isActive else { return }
        isActive = true

        // See ZoomMode.activate() — activate the app *before* the async hop
        // so the user-initiated hotkey context still grants cross-app focus
        // from our `.accessory` activation policy. Without this, Esc routes
        // to the previously frontmost app until the user clicks the overlay.
        NSApp.activate(ignoringOtherApps: true)

        Task { @MainActor in
            do {
                guard CGPreflightScreenCaptureAccess() else {
                    isActive = false
                    handlePermissionDenied()
                    return
                }
                let content = try await SCShareableContent.excludingDesktopWindows(
                    false,
                    onScreenWindowsOnly: true
                )
                guard !content.displays.isEmpty else {
                    isActive = false
                    return
                }
                await present(displays: content.displays)
            } catch {
                isActive = false
                NSLog("MacZoomer: live zoom activation failed: \(error)")
            }
        }
    }

    public func deactivate() {
        guard isActive else { return }
        isActive = false
        stopCursorPolling()
        let toClose = contexts
        contexts.removeAll()
        guard !toClose.isEmpty else { return }

        let remaining = toClose.count
        var done = 0
        for ctx in toClose {
            let window = ctx.window
            ctx.window.liveView.performZoomOutAnimation { [weak window] in
                window?.orderOut(nil)
                done += 1
                if done == remaining {
                    NSCursor.unhide()
                }
            }
            Task.detached { [capturer = ctx.capturer] in
                await capturer.stop()
            }
        }
    }

    /// Tear down windows + streams synchronously, no animation. Mirrors
    /// `ZoomMode.deactivateImmediately()` for future Live Zoom → Live Draw
    /// composition.
    public func deactivateImmediately() {
        guard isActive else { return }
        isActive = false
        stopCursorPolling()
        for ctx in contexts {
            ctx.window.orderOut(nil)
            Task.detached { [capturer = ctx.capturer] in
                await capturer.stop()
            }
        }
        contexts.removeAll()
        NSCursor.unhide()
    }

    // MARK: - Presentation

    private func present(displays: [SCDisplay]) async {
        let initialZoom = preferences.zoomInitialMagnification
        let smoothing = preferences.zoomSmoothing
        let mouseLocationGlobal = NSEvent.mouseLocation

        let nsScreensByID: [CGDirectDisplayID: NSScreen] = Dictionary(
            uniqueKeysWithValues: NSScreen.screens.compactMap { screen in
                screen.displayID.map { ($0, screen) }
            }
        )

        for display in displays {
            guard let screen = nsScreensByID[display.displayID] else { continue }

            let window = LiveZoomWindow(screen: screen)
            window.modeDelegate = self
            window.liveView.smoothing = smoothing

            let screenFrame = screen.frame
            let local = NSPoint(
                x: mouseLocationGlobal.x - screenFrame.origin.x,
                y: mouseLocationGlobal.y - screenFrame.origin.y
            )
            let focal: NSPoint = screenFrame.contains(mouseLocationGlobal)
                ? local
                : NSPoint(x: screenFrame.width / 2, y: screenFrame.height / 2)

            window.liveView.configure(
                sourcePointSize: screenFrame.size,
                initialZoom: CGFloat(initialZoom),
                focalScreen: focal
            )
            window.makeKeyAndOrderFront(nil as AnyObject?)
            window.makeFirstResponder(window)

            let capturer = LiveScreenCapturer()
            let ctx = DisplayContext(window: window, capturer: capturer, display: display)
            contexts.append(ctx)

            // Start the stream. The frame handler is @Sendable and dispatches
            // straight to the AVSampleBufferDisplayLayer (which is thread-safe).
            do {
                try await capturer.start(
                    display: display,
                    showsCursor: true
                ) { [weak window] sampleBuffer in
                    Task { @MainActor [weak window] in
                        window?.liveView.enqueueFrame(sampleBuffer)
                    }
                }
            } catch {
                NSLog("MacZoomer: live zoom stream start failed for display \(display.displayID): \(error)")
            }

            if preferences.zoomAnimate {
                window.liveView.performZoomInAnimation()
            }
        }

        // Re-assert activation + key-window status after the windows are on
        // screen, in case the earlier activate-before-await call was racy.
        NSApp.activate(ignoringOtherApps: true)
        if let topWindow = contexts.last?.window {
            topWindow.makeKey()
            topWindow.makeFirstResponder(topWindow)
        }

        NSCursor.hide()
        startCursorPolling()
    }

    // MARK: - Cursor polling

    private func startCursorPolling() {
        stopCursorPolling()
        lastCursorLocation = NSEvent.mouseLocation
        cursorTimer = Timer.scheduledTimer(withTimeInterval: 1.0 / 60.0, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated {
                self?.pumpCursor()
            }
        }
    }

    private func stopCursorPolling() {
        cursorTimer?.invalidate()
        cursorTimer = nil
    }

    private func pumpCursor() {
        let global = NSEvent.mouseLocation
        guard global != lastCursorLocation else { return }
        lastCursorLocation = global

        for ctx in contexts {
            let frame = ctx.window.screen?.frame ?? ctx.window.frame
            // Only update the display whose screen contains the cursor —
            // the others keep their last focal point so pan stays steady on
            // displays the user isn't on.
            guard frame.contains(global) else { continue }
            let local = NSPoint(
                x: global.x - frame.origin.x,
                y: global.y - frame.origin.y
            )
            ctx.window.liveView.updateFocalScreen(local)
        }
    }

    private func handlePermissionDenied() {
        // On first denial, only trigger the system Screen Recording
        // prompt; stacking our own alert on top simultaneously was
        // confusing. Surface our alert only on subsequent denials.
        if !hasTriggeredSystemPermissionPrompt {
            hasTriggeredSystemPermissionPrompt = true
            permissions.requestIfNeeded(.screenRecording)
            return
        }
        presentPermissionAlert()
    }

    private func presentPermissionAlert() {
        // Prevent the alert from being stacked when the user mashes ⌘4 while
        // it's already up — `runModal()` runs a nested event loop, and
        // queued hotkey presses would otherwise produce multiple alerts.
        guard !isShowingPermissionAlert else { return }
        isShowingPermissionAlert = true
        defer { isShowingPermissionAlert = false }

        let alert = NSAlert()
        alert.messageText = "Screen Recording permission needed"
        alert.informativeText = """
            MacZoomer can't capture the screen for Live Zoom until Screen Recording is enabled in System Settings.

            After enabling it, please quit MacZoomer from the menu bar and relaunch — macOS only applies a new Screen Recording grant when the app is freshly launched.
            """
        alert.addButton(withTitle: "Open System Settings")
        alert.addButton(withTitle: "Cancel")
        if alert.runModal() == .alertFirstButtonReturn {
            permissions.openSettings(for: .screenRecording)
        }
    }

    // MARK: - LiveZoomWindowDelegate

    func liveZoomWindowDidRequestExit(_ window: LiveZoomWindow) {
        deactivate()
    }
}
