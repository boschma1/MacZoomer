import AppKit
import CoreGraphics

/// A completed annotation that the canvas has committed to its drawing list.
public enum DrawingAnnotation: Sendable {
    case freehand(FreehandStroke)
    case line(StraightShape)
    case rectangle(StraightShape)
    case ellipse(StraightShape)
    case arrow(StraightShape)
    case blur(BlurArea)
    case text(TextStamp)

    public var style: PenStyle? {
        switch self {
        case .freehand(let s):   return s.style
        case .line(let s),
             .rectangle(let s),
             .ellipse(let s),
             .arrow(let s):      return s.style
        case .text(let t):       return t.style
        case .blur:              return nil
        }
    }
}

public struct FreehandStroke: Sendable {
    public let style: PenStyle
    public var points: [CGPoint]

    public init(style: PenStyle, points: [CGPoint] = []) {
        self.style = style
        self.points = points
    }
}

public struct StraightShape: Sendable {
    public let style: PenStyle
    public var start: CGPoint
    public var end: CGPoint

    public init(style: PenStyle, start: CGPoint, end: CGPoint) {
        self.style = style
        self.start = start
        self.end = end
    }
}

/// A blur-rect region. Stores the user-selected rectangle (in canvas
/// coordinates) and the canvas renders it by drawing a Gaussian-blurred copy
/// of the frozen background clipped to that rect.
///
/// Replaces the older freehand `BlurStroke`: click-and-drag to pick the area
/// to blur. This matches how most screenshot/redaction tools (CleanShot,
/// Skitch) work and produces more predictable redactions than a brush.
public struct BlurArea: Sendable, Equatable {
    public var rect: CGRect

    public init(rect: CGRect) {
        self.rect = rect
    }
}

/// A committed text annotation. Position is the baseline anchor.
public struct TextStamp: Sendable, Equatable {
    public let style: PenStyle
    public var origin: CGPoint
    public var text: String
    public var fontSize: CGFloat

    public init(style: PenStyle, origin: CGPoint, text: String, fontSize: CGFloat) {
        self.style = style
        self.origin = origin
        self.text = text
        self.fontSize = fontSize
    }
}

/// Background fill behind the strokes. ZoomIt calls these
/// "whiteboard" and "blackboard"; we keep the names familiar.
public enum CanvasBackground: Equatable, Sendable {
    case clear
    case whiteboard
    case blackboard

    public var nsColor: NSColor {
        switch self {
        case .clear:      return .clear
        case .whiteboard: return NSColor(white: 0.98, alpha: 1.0)
        case .blackboard: return NSColor(white: 0.05, alpha: 1.0)
        }
    }
}

/// Which shape primitive a press-and-drag should produce, based on the
/// modifier flags held at mouseDown.
public enum ShapeConstraint: Sendable {
    case freehand
    case line
    case rectangle
    case ellipse
    case arrow

    /// Translates a Cocoa modifier mask to a shape constraint. macOS reserves
    /// `Cmd` for global shortcuts, so we use Shift / Option / Control instead.
    public static func from(modifiers: NSEvent.ModifierFlags) -> ShapeConstraint {
        let m = modifiers.intersection(.deviceIndependentFlagsMask)
        if m.contains(.shift) && m.contains(.option) { return .arrow }
        if m.contains(.control) { return .ellipse }
        if m.contains(.option)  { return .rectangle }
        if m.contains(.shift)   { return .line }
        return .freehand
    }
}
