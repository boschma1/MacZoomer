import AppKit

/// Borderless full-screen window pinned to one display, hosting the Zoom view.
/// Captures keyboard + mouse input for its screen.
final class ZoomWindow: NSWindow {
    let zoomView: ZoomView
    weak var modeDelegate: ZoomWindowDelegate?

    init(screen: NSScreen) {
        self.zoomView = ZoomView(frame: NSRect(origin: .zero, size: screen.frame.size))
        super.init(
            contentRect: screen.frame,
            styleMask: .borderless,
            backing: .buffered,
            defer: false,
            screen: screen
        )
        isOpaque = false
        backgroundColor = .black
        hasShadow = false
        level = .screenSaver
        ignoresMouseEvents = false
        acceptsMouseMovedEvents = true
        collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary]
        isReleasedWhenClosed = false
        animationBehavior = .none
        contentView = zoomView
    }

    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { true }

    // MARK: - Input forwarding

    override func mouseMoved(with event: NSEvent) {
        let point = convertEventLocation(event)
        zoomView.updateFocalScreen(point)
    }

    override func mouseDragged(with event: NSEvent) {
        let point = convertEventLocation(event)
        zoomView.updateFocalScreen(point)
    }

    override func scrollWheel(with event: NSEvent) {
        let delta = event.scrollingDeltaY * ZoomGeometry.stepScrollMultiplier
        zoomView.adjustZoom(by: delta)
    }

    override func keyDown(with event: NSEvent) {
        switch event.keyCode {
        case 53: // Esc
            modeDelegate?.zoomWindowDidRequestExit(self)
        case 126: // Up arrow
            zoomView.adjustZoom(by: ZoomGeometry.stepArrow)
        case 125: // Down arrow
            zoomView.adjustZoom(by: -ZoomGeometry.stepArrow)
        default:
            super.keyDown(with: event)
        }
    }

    override func rightMouseDown(with event: NSEvent) {
        modeDelegate?.zoomWindowDidRequestExit(self)
    }

    private func convertEventLocation(_ event: NSEvent) -> NSPoint {
        // `event.locationInWindow` is in window coords; the view fills the window.
        event.locationInWindow
    }
}

protocol ZoomWindowDelegate: AnyObject {
    @MainActor func zoomWindowDidRequestExit(_ window: ZoomWindow)
}
