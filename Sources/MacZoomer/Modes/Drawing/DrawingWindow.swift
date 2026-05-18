import AppKit

/// Borderless full-screen window for LiveDraw — a transparent canvas on top
/// of the live desktop. Owns a `DrawingCanvas` and accepts mouse + keyboard input.
final class DrawingWindow: NSWindow {
    let canvas: DrawingCanvas

    init(screen: NSScreen, state: DrawingState) {
        self.canvas = DrawingCanvas(frame: NSRect(origin: .zero, size: screen.frame.size), state: state)
        // 4-arg super.init + setFrame(_:display:) avoids AppKit's internal
        // re-dispatch of `init(...:screen:)` through the 4-arg variant, which
        // would otherwise re-invoke the override below and silently swap
        // `canvas` for one that observes a different `DrawingState`.
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
        acceptsMouseMovedEvents = true
        collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary]
        isReleasedWhenClosed = false
        animationBehavior = .none
        contentView = canvas
        setFrame(screen.frame, display: false)
    }

    /// Safety override so the inherited initializer isn't a synthesized fatal
    /// trap. `init(screen:state:)` is the supported entry point.
    override init(
        contentRect: NSRect,
        styleMask style: NSWindow.StyleMask,
        backing backingStoreType: NSWindow.BackingStoreType,
        defer flag: Bool
    ) {
        self.canvas = DrawingCanvas(frame: NSRect(origin: .zero, size: contentRect.size), state: DrawingState())
        super.init(
            contentRect: contentRect,
            styleMask: style,
            backing: backingStoreType,
            defer: flag
        )
    }

    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { true }
}
