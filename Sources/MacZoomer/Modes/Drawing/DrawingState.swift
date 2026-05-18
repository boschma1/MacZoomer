import AppKit
import Combine

/// In-memory state for an active drawing session: current tool, pen,
/// background, committed annotations, and in-progress text entry.
@MainActor
public final class DrawingState: ObservableObject {
    @Published public private(set) var currentColor: PenColor = .red
    @Published public private(set) var currentWidth: CGFloat = PenStyle.defaultWidth
    @Published public private(set) var isHighlight: Bool = false
    @Published public private(set) var background: CanvasBackground = .clear
    @Published public private(set) var annotations: [DrawingAnnotation] = []
    @Published public private(set) var currentTool: DrawingTool = .ink

    /// Text being composed right now — placed but not yet committed. Becomes
    /// a `.text` annotation when the user hits Enter/Esc or clicks elsewhere.
    @Published public var inProgressText: TextStamp?

    public static let defaultTextFontSize: CGFloat = 36.0
    public static let minTextFontSize: CGFloat = 12.0
    public static let maxTextFontSize: CGFloat = 200.0
    public static let textFontStep: CGFloat = 2.0

    public init() {}

    public var currentStyle: PenStyle {
        PenStyle(color: currentColor, width: currentWidth, isHighlight: isHighlight)
    }

    // MARK: - Tool changes

    public func setTool(_ tool: DrawingTool) {
        if currentTool == .text && tool != .text {
            commitInProgressText()
        }
        currentTool = tool
    }

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
        inProgressText = nil
    }

    // MARK: - Text editing

    public func beginText(at origin: CGPoint, fontSize: CGFloat? = nil) {
        commitInProgressText()
        inProgressText = TextStamp(
            style: currentStyle,
            origin: origin,
            text: "",
            fontSize: fontSize ?? Self.defaultTextFontSize
        )
    }

    public func appendText(_ string: String) {
        guard var draft = inProgressText else { return }
        draft.text.append(contentsOf: string)
        inProgressText = draft
    }

    public func deleteBackwardInText() {
        guard var draft = inProgressText else { return }
        if !draft.text.isEmpty {
            draft.text.removeLast()
            inProgressText = draft
        }
    }

    public func adjustTextFontSize(by delta: CGFloat) {
        guard var draft = inProgressText else { return }
        let next = min(max(draft.fontSize + delta, Self.minTextFontSize), Self.maxTextFontSize)
        draft.fontSize = next
        inProgressText = draft
    }

    /// Move the in-progress text to the committed annotations list (if any).
    @discardableResult
    public func commitInProgressText() -> Bool {
        guard let draft = inProgressText else { return false }
        inProgressText = nil
        guard !draft.text.isEmpty else { return false }
        annotations.append(.text(draft))
        return true
    }

    public func cancelInProgressText() {
        inProgressText = nil
    }
}
