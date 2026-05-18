import AppKit

/// Result of a region drag: the screen the selection started on plus the
/// rect in that screen's local points (bottom-left origin).
public struct RegionSelection: Sendable {
    public let screenLocalRect: NSRect
    public let screenFrame: NSRect
    public let screenDisplayID: CGDirectDisplayID
    public let backingScale: CGFloat
}

/// Presents a full-screen dim overlay on every display and lets the user
/// drag a selection rectangle. Mouse-up returns the selection; Esc / right
/// click cancels.
@MainActor
public final class RegionSelector: NSObject, RegionSelectorWindowDelegate {
    public typealias Completion = (RegionSelection?) -> Void

    private var windows: [RegionSelectorWindow] = []
    private var activeStartPoint: NSPoint?
    private var activeWindow: RegionSelectorWindow?
    private var completion: Completion?

    public override init() {
        super.init()
    }

    public var isActive: Bool { !windows.isEmpty }

    public func present(completion: @escaping Completion) {
        guard !isActive else {
            completion(nil)
            return
        }
        self.completion = completion

        for screen in NSScreen.screens {
            let window = RegionSelectorWindow(screen: screen)
            window.selectorDelegate = self
            window.makeKeyAndOrderFront(nil as AnyObject?)
            window.makeFirstResponder(window)
            windows.append(window)
        }
        NSCursor.crosshair.push()
    }

    private func tearDown() {
        NSCursor.pop()
        for window in windows {
            window.orderOut(nil)
        }
        windows.removeAll()
        activeStartPoint = nil
        activeWindow = nil
    }

    private func finish(with selection: RegionSelection?) {
        let cb = completion
        completion = nil
        tearDown()
        cb?(selection)
    }

    // MARK: - RegionSelectorWindowDelegate

    func regionSelector(_ window: RegionSelectorWindow, didBeginDragAt point: NSPoint) {
        activeWindow = window
        activeStartPoint = point
        window.selectorView.selectionRect = NSRect(origin: point, size: .zero)
    }

    func regionSelector(_ window: RegionSelectorWindow, didDragTo point: NSPoint) {
        guard let start = activeStartPoint, activeWindow === window else { return }
        window.selectorView.selectionRect = RegionSelectorGeometry.rect(from: start, to: point)
    }

    func regionSelector(_ window: RegionSelectorWindow, didEndDragAt point: NSPoint) {
        guard let start = activeStartPoint, activeWindow === window else {
            finish(with: nil)
            return
        }
        let rect = RegionSelectorGeometry.rect(from: start, to: point)
        // Reject zero-area or trivial selections; treat as cancel.
        guard rect.width >= 2, rect.height >= 2 else {
            finish(with: nil)
            return
        }
        guard let screen = window.screen,
              let displayID = screen.displayID else {
            finish(with: nil)
            return
        }
        let selection = RegionSelection(
            screenLocalRect: rect,
            screenFrame: screen.frame,
            screenDisplayID: displayID,
            backingScale: screen.backingScaleFactor
        )
        finish(with: selection)
    }

    func regionSelectorDidCancel(_ window: RegionSelectorWindow) {
        finish(with: nil)
    }
}
