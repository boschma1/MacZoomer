import AppKit

/// Borderless full-screen window pinned to one display, hosting the Zoom view.
/// Captures keyboard + mouse input for its screen.
final class ZoomWindow: NSWindow {
    let zoomView: ZoomView
    weak var modeDelegate: ZoomWindowDelegate?

    init(screen: NSScreen) {
        self.zoomView = ZoomView(frame: NSRect(origin: .zero, size: screen.frame.size))
        // We use the 4-argument super.init *and* setFrame(_:display:) below to
        // avoid AppKit's internal re-dispatch of `init(...:screen:)` through
        // `[self initWithContentRect:styleMask:backing:defer:]` — that
        // re-dispatch invokes the 4-arg override again and reassigns
        // `zoomView`, silently dropping the one we just stored.
        super.init(
            contentRect: screen.frame,
            styleMask: .borderless,
            backing: .buffered,
            defer: false
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
        setFrame(screen.frame, display: false)
    }

    /// Safety override so the inherited initializer isn't a synthesized fatal
    /// trap if anything (NIB loading, KVC, internal AppKit recreation) ever
    /// calls it directly. Our own `init(screen:)` no longer triggers this path.
    override init(
        contentRect: NSRect,
        styleMask style: NSWindow.StyleMask,
        backing backingStoreType: NSWindow.BackingStoreType,
        defer flag: Bool
    ) {
        self.zoomView = ZoomView(frame: NSRect(origin: .zero, size: contentRect.size))
        super.init(
            contentRect: contentRect,
            styleMask: style,
            backing: backingStoreType,
            defer: flag
        )
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
