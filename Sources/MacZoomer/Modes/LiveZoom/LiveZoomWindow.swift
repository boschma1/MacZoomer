import AppKit

/// Borderless full-screen window pinned to one display, hosting `LiveZoomView`.
/// Mirrors the input-handling shape of `ZoomWindow` so the two zoom modes
/// feel identical to the user.
final class LiveZoomWindow: NSWindow {
    let liveView: LiveZoomView
    weak var modeDelegate: LiveZoomWindowDelegate?

    init(screen: NSScreen) {
        self.liveView = LiveZoomView(frame: NSRect(origin: .zero, size: screen.frame.size))
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
        contentView = liveView
        setFrame(screen.frame, display: false)
    }

    /// Safety override for NIB/KVC paths — `init(screen:)` no longer triggers
    /// the inherited re-dispatch through this initializer.
    override init(
        contentRect: NSRect,
        styleMask style: NSWindow.StyleMask,
        backing backingStoreType: NSWindow.BackingStoreType,
        defer flag: Bool
    ) {
        self.liveView = LiveZoomView(frame: NSRect(origin: .zero, size: contentRect.size))
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
        let point = event.locationInWindow
        liveView.updateFocalScreen(point)
    }

    override func mouseDragged(with event: NSEvent) {
        let point = event.locationInWindow
        liveView.updateFocalScreen(point)
    }

    override func scrollWheel(with event: NSEvent) {
        let delta = event.scrollingDeltaY * ZoomGeometry.stepScrollMultiplier
        liveView.adjustZoom(by: delta)
    }

    override func keyDown(with event: NSEvent) {
        switch event.keyCode {
        case 53: // Esc
            modeDelegate?.liveZoomWindowDidRequestExit(self)
        case 126: // Up arrow
            liveView.adjustZoom(by: ZoomGeometry.stepArrow)
        case 125: // Down arrow
            liveView.adjustZoom(by: -ZoomGeometry.stepArrow)
        default:
            super.keyDown(with: event)
        }
    }

    override func rightMouseDown(with event: NSEvent) {
        modeDelegate?.liveZoomWindowDidRequestExit(self)
    }
}

protocol LiveZoomWindowDelegate: AnyObject {
    @MainActor func liveZoomWindowDidRequestExit(_ window: LiveZoomWindow)
}
