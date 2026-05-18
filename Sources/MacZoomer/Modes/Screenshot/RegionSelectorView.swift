import AppKit

/// Transparent dim overlay that draws the in-progress selection rectangle.
/// One per display.
final class RegionSelectorView: NSView {
    var selectionRect: NSRect? {
        didSet { needsDisplay = true }
    }

    /// Tint colour applied to the screen behind the selection. The selection
    /// rectangle itself is rendered with full clarity (cleared from the dim).
    var dimColor: NSColor = NSColor.black.withAlphaComponent(0.32)
    var selectionStrokeColor: NSColor = .white
    var selectionStrokeWidth: CGFloat = 1.0

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        wantsLayer = true
        layer?.backgroundColor = NSColor.clear.cgColor
    }

    required init?(coder: NSCoder) {
        super.init(coder: coder)
        wantsLayer = true
    }

    override var acceptsFirstResponder: Bool { true }
    override var isFlipped: Bool { false }

    override func resetCursorRects() {
        super.resetCursorRects()
        addCursorRect(bounds, cursor: .crosshair)
    }

    override func draw(_ dirtyRect: NSRect) {
        guard let ctx = NSGraphicsContext.current?.cgContext else { return }
        ctx.setFillColor(dimColor.cgColor)
        ctx.fill(bounds)

        if let rect = selectionRect {
            // Punch out the selection area so the live screen shows through
            // without the dim overlay.
            ctx.setBlendMode(.clear)
            ctx.fill(rect)
            ctx.setBlendMode(.normal)

            // Stroke the selection border.
            ctx.setStrokeColor(selectionStrokeColor.cgColor)
            ctx.setLineWidth(selectionStrokeWidth)
            ctx.stroke(rect.insetBy(dx: 0.5, dy: 0.5))
        }
    }
}

public enum RegionSelectorGeometry {
    /// Computes a normalised positive-area rect from two drag points.
    public static func rect(from start: NSPoint, to current: NSPoint) -> NSRect {
        NSRect(
            x: min(start.x, current.x),
            y: min(start.y, current.y),
            width: abs(current.x - start.x),
            height: abs(current.y - start.y)
        )
    }
}
