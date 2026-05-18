import AppKit
import CoreGraphics

/// Pure-function helpers for shape geometry — kept side-effect-free so they
/// can be unit-tested without an app context.
public enum DrawingGeometry {
    /// Constrains a line endpoint to a multiple of 15° when `snapEnabled` is true.
    public static func snapAngle(from start: CGPoint, to end: CGPoint, snapEnabled: Bool) -> CGPoint {
        guard snapEnabled else { return end }
        let dx = end.x - start.x
        let dy = end.y - start.y
        let length = (dx * dx + dy * dy).squareRoot()
        guard length > 0 else { return end }
        let stepRadians: CGFloat = .pi / 12 // 15°
        let angle = atan2(dy, dx)
        let snapped = (angle / stepRadians).rounded() * stepRadians
        return CGPoint(
            x: start.x + cos(snapped) * length,
            y: start.y + sin(snapped) * length
        )
    }

    /// Builds a Bezier path for an arrowhead at `end`, pointing from `start`.
    public static func arrowheadPath(from start: CGPoint, to end: CGPoint, strokeWidth: CGFloat) -> NSBezierPath {
        let dx = end.x - start.x
        let dy = end.y - start.y
        let length = (dx * dx + dy * dy).squareRoot()
        let path = NSBezierPath()
        guard length > 0 else { return path }
        let angle = atan2(dy, dx)
        let headLength = max(strokeWidth * 4, 14)
        let headAngle: CGFloat = .pi / 7 // ~25°
        let left = CGPoint(
            x: end.x - cos(angle - headAngle) * headLength,
            y: end.y - sin(angle - headAngle) * headLength
        )
        let right = CGPoint(
            x: end.x - cos(angle + headAngle) * headLength,
            y: end.y - sin(angle + headAngle) * headLength
        )
        path.move(to: end)
        path.line(to: left)
        path.line(to: right)
        path.close()
        return path
    }

    public static func rect(from a: CGPoint, to b: CGPoint) -> CGRect {
        CGRect(
            x: min(a.x, b.x),
            y: min(a.y, b.y),
            width: abs(b.x - a.x),
            height: abs(b.y - a.y)
        )
    }
}
