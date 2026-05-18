import AppKit

/// Borderless full-screen window hosting `RegionSelectorView` for one display.
/// Forwards mouse + key events to the owning `RegionSelector`.
final class RegionSelectorWindow: NSWindow {
    let selectorView: RegionSelectorView
    weak var selectorDelegate: RegionSelectorWindowDelegate?

    init(screen: NSScreen) {
        self.selectorView = RegionSelectorView(frame: NSRect(origin: .zero, size: screen.frame.size))
        super.init(
            contentRect: screen.frame,
            styleMask: .borderless,
            backing: .buffered,
            defer: false
        )
        isOpaque = false
        backgroundColor = .clear
        hasShadow = false
        level = .screenSaver
        ignoresMouseEvents = false
        acceptsMouseMovedEvents = false
        collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary]
        isReleasedWhenClosed = false
        animationBehavior = .none
        contentView = selectorView
        setFrame(screen.frame, display: false)
        invalidateShadow()
    }

    override init(
        contentRect: NSRect,
        styleMask style: NSWindow.StyleMask,
        backing backingStoreType: NSWindow.BackingStoreType,
        defer flag: Bool
    ) {
        self.selectorView = RegionSelectorView(frame: NSRect(origin: .zero, size: contentRect.size))
        super.init(
            contentRect: contentRect,
            styleMask: style,
            backing: backingStoreType,
            defer: flag
        )
    }

    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { true }

    override func mouseDown(with event: NSEvent) {
        selectorDelegate?.regionSelector(self, didBeginDragAt: event.locationInWindow)
    }

    override func mouseDragged(with event: NSEvent) {
        selectorDelegate?.regionSelector(self, didDragTo: event.locationInWindow)
    }

    override func mouseUp(with event: NSEvent) {
        selectorDelegate?.regionSelector(self, didEndDragAt: event.locationInWindow)
    }

    override func keyDown(with event: NSEvent) {
        switch event.keyCode {
        case 53: // Esc
            selectorDelegate?.regionSelectorDidCancel(self)
        default:
            super.keyDown(with: event)
        }
    }

    override func rightMouseDown(with event: NSEvent) {
        selectorDelegate?.regionSelectorDidCancel(self)
    }
}

protocol RegionSelectorWindowDelegate: AnyObject {
    @MainActor func regionSelector(_ window: RegionSelectorWindow, didBeginDragAt point: NSPoint)
    @MainActor func regionSelector(_ window: RegionSelectorWindow, didDragTo point: NSPoint)
    @MainActor func regionSelector(_ window: RegionSelectorWindow, didEndDragAt point: NSPoint)
    @MainActor func regionSelectorDidCancel(_ window: RegionSelectorWindow)
}
