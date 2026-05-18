import AppKit

/// Top-level controller for the standalone drawing overlay (the ZoomIt
/// "Draw" / "LiveDraw" feature — a transparent canvas spanning every display
/// that the user can annotate while the desktop is live underneath).
///
/// Zoom+Draw composition (drawing on top of the frozen Zoom Mode image) is
/// deferred to a follow-up phase; see plan.md.
@MainActor
public final class DrawingMode: ObservableObject {
    public let state = DrawingState()
    private var windows: [DrawingWindow] = []
    public private(set) var isActive = false

    public init() {}

    public func activate() {
        guard !isActive else { return }
        isActive = true

        for screen in NSScreen.screens {
            let window = DrawingWindow(screen: screen, state: state)
            window.canvas.onExit = { [weak self] in self?.deactivate() }
            window.makeKeyAndOrderFront(nil as AnyObject?)
            window.makeFirstResponder(window.canvas)
            windows.append(window)
        }
    }

    public func deactivate() {
        guard isActive else { return }
        isActive = false
        for window in windows {
            window.orderOut(nil)
        }
        windows.removeAll()
        state.eraseAll()
    }
}
