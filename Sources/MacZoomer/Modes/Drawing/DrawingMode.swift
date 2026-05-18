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
    private let capturer = ScreenCapturer()

    private var windows: [DrawingWindow] = []
    public private(set) var isActive = false

    /// Set when capture fails so blur strokes degrade gracefully.
    public private(set) var hasFrozenBackground = false

    public init() {}

    /// Capture every connected display and present the draw overlay over it.
    public func activate() {
        guard !isActive else { return }
        isActive = true

        Task { @MainActor in
            var captures: [DisplayCapture] = []
            do {
                captures = try await capturer.captureAllDisplays()
            } catch {
                // Capture failed — fall back to a transparent overlay so the
                // user can still draw and type. Blur strokes won't render
                // anything visible but the rest of the tools still work.
                NSLog("MacZoomer: draw capture failed: \(error). Falling back to transparent overlay.")
            }
            present(captures: captures)
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
    }
}
