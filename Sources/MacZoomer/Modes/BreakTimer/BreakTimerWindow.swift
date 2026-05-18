import AppKit

/// Full-screen window that hosts the `BreakTimerView` on one display.
final class BreakTimerWindow: NSWindow {
    let timerView: BreakTimerView

    var onExit: (() -> Void)?
    var onTogglePause: (() -> Void)?
    var onAdjust: ((TimeInterval) -> Void)?
    var onReset: (() -> Void)?

    init(screen: NSScreen, state: BreakTimerState, message: String, opacity: CGFloat) {
        self.timerView = BreakTimerView(
            frame: NSRect(origin: .zero, size: screen.frame.size),
            state: state,
            message: message,
            opacity: opacity
        )
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
        collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary]
        isReleasedWhenClosed = false
        animationBehavior = .none
        contentView = timerView
        setFrame(screen.frame, display: false)
    }

    override init(
        contentRect: NSRect,
        styleMask style: NSWindow.StyleMask,
        backing backingStoreType: NSWindow.BackingStoreType,
        defer flag: Bool
    ) {
        self.timerView = BreakTimerView(
            frame: NSRect(origin: .zero, size: contentRect.size),
            state: BreakTimerState(initialDuration: 0),
            message: "",
            opacity: 1.0
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

    override func keyDown(with event: NSEvent) {
        switch event.keyCode {
        case 53: // Esc
            onExit?()
        case 49: // Space — pause/resume
            onTogglePause?()
        case 126: // Up — +1 minute
            onAdjust?(60)
        case 125: // Down — −1 minute
            onAdjust?(-60)
        case 124: // Right — +10 seconds
            onAdjust?(10)
        case 123: // Left — −10 seconds
            onAdjust?(-10)
        case 15: // R — reset to initial duration
            onReset?()
        default:
            super.keyDown(with: event)
        }
    }

    override func rightMouseDown(with event: NSEvent) {
        onExit?()
    }
}
