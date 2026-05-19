import AppKit

/// Top-level controller for the drawing overlay (the ZoomIt "Draw" feature
/// — a full-screen canvas that the user can annotate after their current
/// screen content has been frozen as a still image).
///
/// `activate(frozenImages:)` accepts pre-captured per-screen images, which is
/// how the Zoom→Draw composition hands the current zoomed view to Draw mode.
/// `activate()` does the screen capture itself.
@MainActor
public final class DrawingMode: ObservableObject {
    public let state = DrawingState()
    private let permissions: PermissionCoordinator
    private let capturer = ScreenCapturer()

    private var windows: [DrawingWindow] = []
    public private(set) var isActive = false

    /// Set when capture fails so blur strokes degrade gracefully.
    public private(set) var hasFrozenBackground = false

    /// We call `CGRequestScreenCaptureAccess()` at most once per process to
    /// register a TCC entry and trigger the system permission prompt — same
    /// pattern as ZoomMode. Subsequent denials route to our friendly alert.
    private var hasTriggeredSystemPermissionPrompt = false
    private var isShowingPermissionAlert = false

    public init(permissions: PermissionCoordinator) {
        self.permissions = permissions
    }

    /// Capture every connected display and present the draw overlay over it.
    public func activate() {
        guard !isActive else { return }
        isActive = true

        // Activate the app *before* the async capture hop. See ZoomMode for
        // the full reasoning: as an `LSUIElement` / `.accessory` app, the
        // hotkey is our user-initiated event window for stealing cross-app
        // focus, and that grant expires after an `await`. Without this the
        // draw overlay would appear but keystrokes/mouse cursor still belong
        // to the previously frontmost app, so the user has to click into the
        // canvas before the pencil cursor appears and drawing starts.
        NSApp.activate(ignoringOtherApps: true)

        Task { @MainActor in
            do {
                let captures = try await capturer.captureAllDisplays()
                present(captures: captures)
            } catch ScreenCaptureError.permissionDenied {
                // Screen Recording is required to freeze the screen behind the
                // canvas (which also makes the Blur tool useful — without it,
                // blur strokes fall back to opaque black with no underlying
                // image to smudge). Mirror ZoomMode: prompt the user instead
                // of silently degrading to a transparent overlay.
                isActive = false
                handlePermissionDenied()
            } catch {
                // Other capture failures (e.g. transient SCStream errors) —
                // fall back to a transparent overlay so the user can still
                // draw, type, and use shapes. Blur strokes will redact as
                // opaque black until next reactivation.
                NSLog("MacZoomer: draw capture failed: \(error). Falling back to transparent overlay.")
                present(captures: [])
            }
        }
    }

    /// Variant used by the Zoom→Draw handoff. The caller has already rendered
    /// each display to a CGImage (typically the current zoomed view), so we
    /// skip the screen-capture step.
    public func activate(frozenImages: [DisplayCapture]) {
        guard !isActive else { return }
        isActive = true
        present(captures: frozenImages)
    }

    public func deactivate() {
        guard isActive else { return }
        isActive = false
        for window in windows {
            window.orderOut(nil)
        }
        windows.removeAll()
        state.eraseAll()
        hasFrozenBackground = false
    }

    private func present(captures: [DisplayCapture]) {
        hasFrozenBackground = !captures.isEmpty
        let capturesByScreen: [NSScreen: DisplayCapture] = Dictionary(
            uniqueKeysWithValues: captures.map { ($0.screen, $0) }
        )

        for screen in NSScreen.screens {
            let capture = capturesByScreen[screen]
            let window = DrawingWindow(
                screen: screen,
                state: state,
                frozenImage: capture?.image,
                backingScale: capture?.backingScale ?? screen.backingScaleFactor
            )
            window.canvas.onExit = { [weak self] in self?.deactivate() }
            window.makeKeyAndOrderFront(nil as AnyObject?)
            window.makeFirstResponder(window.canvas)
            windows.append(window)
        }

        // Re-assert activation + key-window status after the windows are on
        // screen. `makeKeyAndOrderFront` only grants key status if the app
        // is active, so without this the canvas wouldn't receive mouse-moved
        // events (so the pencil cursor wouldn't show) until the user clicked.
        // Covers both the hotkey path and the Zoom→Draw handoff path.
        NSApp.activate(ignoringOtherApps: true)
        if let topWindow = windows.last {
            topWindow.makeKey()
            topWindow.makeFirstResponder(topWindow.canvas)
        }
    }

    // MARK: - Permission denial

    private func handlePermissionDenied() {
        // First denial: trigger only the system prompt — stacking our alert
        // on top of it was confusing. If permission is still not granted on
        // the next hotkey press, surface our friendly alert instead.
        if !hasTriggeredSystemPermissionPrompt {
            hasTriggeredSystemPermissionPrompt = true
            permissions.requestIfNeeded(.screenRecording)
            return
        }
        presentPermissionAlert()
    }

    private func presentPermissionAlert() {
        // Re-entry guard: NSAlert.runModal() runs a nested event loop, and
        // queued hotkey presses while it's open would otherwise stack alerts.
        guard !isShowingPermissionAlert else { return }
        isShowingPermissionAlert = true
        defer { isShowingPermissionAlert = false }

        let alert = NSAlert()
        alert.messageText = "Screen Recording permission needed"
        alert.informativeText = """
            MacZoomer can't freeze the screen behind the Draw canvas until Screen Recording is enabled in System Settings. Without it, the Blur tool also has no image to smudge and falls back to opaque black.

            After enabling it, please quit MacZoomer from the menu bar and relaunch — macOS only applies a new Screen Recording grant when the app is freshly launched.
            """
        alert.addButton(withTitle: "Open System Settings")
        alert.addButton(withTitle: "Cancel")
        if alert.runModal() == .alertFirstButtonReturn {
            permissions.openSettings(for: .screenRecording)
        }
    }
}
