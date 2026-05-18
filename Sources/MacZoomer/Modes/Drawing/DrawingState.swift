import AppKit
import Combine

/// In-memory state for an active drawing session: current pen, background,
/// committed annotations, and undo stack.
@MainActor
public final class DrawingState: ObservableObject {
    @Published public private(set) var currentColor: PenColor = .red
    @Published public private(set) var currentWidth: CGFloat = PenStyle.defaultWidth
    @Published public private(set) var isHighlight: Bool = false
    @Published public private(set) var background: CanvasBackground = .clear
    @Published public private(set) var annotations: [DrawingAnnotation] = []

    public init() {}

    public var currentStyle: PenStyle {
        PenStyle(color: currentColor, width: currentWidth, isHighlight: isHighlight)
    }

    // MARK: - Tool changes

    public func setColor(_ color: PenColor, highlight: Bool) {
        currentColor = color
        isHighlight = highlight
    }

    public func setBackground(_ bg: CanvasBackground) {
        background = bg
    }

    public func adjustWidth(by delta: CGFloat) {
        let next = min(max(currentWidth + delta, PenStyle.minWidth), PenStyle.maxWidth)
        currentWidth = next
    }

    public func setWidth(_ width: CGFloat) {
        currentWidth = min(max(width, PenStyle.minWidth), PenStyle.maxWidth)
    }

    // MARK: - Annotation list

    public func commit(_ annotation: DrawingAnnotation) {
        annotations.append(annotation)
    }

    public func undoLast() {
        guard !annotations.isEmpty else { return }
        annotations.removeLast()
    }

    public func eraseAll() {
        annotations.removeAll()
        background = .clear
    }
}
