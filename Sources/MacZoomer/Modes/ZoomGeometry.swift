import AppKit
import CoreGraphics

/// Pure-math helpers for Zoom Mode geometry. Kept free of AppKit/CoreAnimation
/// state so they can be unit-tested without a running app.
public enum ZoomGeometry {
    public static let minLevel: CGFloat = 1.0
    public static let maxLevel: CGFloat = 10.0
    public static let stepScrollMultiplier: CGFloat = 0.0025
    public static let stepArrow: CGFloat = 0.25

    public static func clamp(level: CGFloat) -> CGFloat {
        min(max(level, minLevel), maxLevel)
    }

    /// Given a captured source image's size in points, the destination view's
    /// size, the current zoom level, and the source-image point that should
    /// appear at `focalScreen` (a point in the destination view), returns the
    /// frame the image layer should have in destination coordinates.
    public static func imageLayerFrame(
        sourcePointSize: CGSize,
        zoomLevel: CGFloat,
        focalSource: CGPoint,
        focalScreen: CGPoint
    ) -> CGRect {
        let scaled = CGSize(
            width: sourcePointSize.width * zoomLevel,
            height: sourcePointSize.height * zoomLevel
        )
        return CGRect(
            x: focalScreen.x - focalSource.x * zoomLevel,
            y: focalScreen.y - focalSource.y * zoomLevel,
            width: scaled.width,
            height: scaled.height
        )
    }

    /// Maps a point in destination view coordinates back to the source image
    /// coordinate space, given the current focal mapping. Useful when the
    /// user moves the mouse and we want to keep the cursor anchored to the
    /// same source pixel.
    public static func sourcePoint(
        forScreenPoint screenPoint: CGPoint,
        zoomLevel: CGFloat,
        focalSource: CGPoint,
        focalScreen: CGPoint
    ) -> CGPoint {
        CGPoint(
            x: focalSource.x + (screenPoint.x - focalScreen.x) / zoomLevel,
            y: focalSource.y + (screenPoint.y - focalScreen.y) / zoomLevel
        )
    }

    /// Clamps a focal-source point so that the image still covers the entire
    /// destination view (no black bars on the edges). When the image is
    /// smaller than the destination at this zoom level, returns the source
    /// midpoint so the image is centered.
    public static func clampFocalSource(
        _ focal: CGPoint,
        zoomLevel: CGFloat,
        sourcePointSize: CGSize,
        destinationSize: CGSize,
        focalScreen: CGPoint
    ) -> CGPoint {
        let scaledW = sourcePointSize.width * zoomLevel
        let scaledH = sourcePointSize.height * zoomLevel

        let minX: CGFloat
        let maxX: CGFloat
        if scaledW <= destinationSize.width {
            let centered = sourcePointSize.width / 2
            minX = centered
            maxX = centered
        } else {
            minX = focalScreen.x / zoomLevel
            maxX = sourcePointSize.width - (destinationSize.width - focalScreen.x) / zoomLevel
        }
        let minY: CGFloat
        let maxY: CGFloat
        if scaledH <= destinationSize.height {
            let centered = sourcePointSize.height / 2
            minY = centered
            maxY = centered
        } else {
            minY = focalScreen.y / zoomLevel
            maxY = sourcePointSize.height - (destinationSize.height - focalScreen.y) / zoomLevel
        }
        return CGPoint(
            x: min(max(focal.x, minX), maxX),
            y: min(max(focal.y, minY), maxY)
        )
    }
}
