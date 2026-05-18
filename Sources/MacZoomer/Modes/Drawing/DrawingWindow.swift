import AppKit

/// Borderless full-screen window for LiveDraw — a transparent canvas on top
/// of the live desktop. Owns a `DrawingCanvas` and accepts mouse + keyboard input.
final class DrawingWindow: NSWindow {
    let canvas: DrawingCanvas

    init(screen: NSScreen, state: DrawingState) {
        self.canvas = DrawingCanvas(frame: NSRect(origin: .zero, size: screen.frame.size), state: state)
        super.init(
            contentRect: screen.frame,
            styleMask: .borderless,
            backing: .buffered,
            defer: false,
            screen: screen
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
    }

    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { true }
}
