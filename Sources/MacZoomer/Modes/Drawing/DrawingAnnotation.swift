import AppKit
import CoreGraphics

/// A completed annotation that the canvas has committed to its drawing list.
public enum DrawingAnnotation: Sendable {
    case freehand(FreehandStroke)
    case line(StraightShape)
    case rectangle(StraightShape)
    case ellipse(StraightShape)
    case arrow(StraightShape)
    case blur(BlurStroke)
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

/// A blur-pen stroke. Has only a width (the brush thickness) and a path; the
/// canvas renders it by drawing a Gaussian-blurred copy of the frozen
/// background clipped to the path's stroke.
public struct BlurStroke: Sendable {
    public let width: CGFloat
    public var points: [CGPoint]

    public init(width: CGFloat, points: [CGPoint] = []) {
        self.width = width
        self.points = points
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
