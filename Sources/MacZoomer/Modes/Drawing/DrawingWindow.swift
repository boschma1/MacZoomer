import AppKit

/// Borderless full-screen window for Draw — hosts a `DrawingCanvas` and the
/// frozen-screen background image (if capture succeeded). Captures mouse +
/// keyboard input for its screen.
final class DrawingWindow: NSWindow {
    let canvas: DrawingCanvas

    init(
        screen: NSScreen,
        state: DrawingState,
        frozenImage: CGImage? = nil,
        backingScale: CGFloat = 2.0
    ) {
        self.canvas = DrawingCanvas(
            frame: NSRect(origin: .zero, size: screen.frame.size),
            state: state,
            frozenBackground: frozenImage,
            backingScale: backingScale
        )
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
    /// trap. `init(screen:state:frozenImage:backingScale:)` is the supported
    /// entry point.
    override init(
        contentRect: NSRect,
        styleMask style: NSWindow.StyleMask,
        backing backingStoreType: NSWindow.BackingStoreType,
        defer flag: Bool
    ) {
        self.canvas = DrawingCanvas(
            frame: NSRect(origin: .zero, size: contentRect.size),
            state: DrawingState(),
            frozenBackground: nil,
            backingScale: 2.0
        )
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
