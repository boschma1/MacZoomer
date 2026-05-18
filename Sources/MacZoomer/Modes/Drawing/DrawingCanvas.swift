import AppKit
import Combine

/// NSView that renders committed annotations, captures mouse input for new
/// strokes/shapes, and routes keyboard shortcuts to its `DrawingState`.
final class DrawingCanvas: NSView {
    let state: DrawingState

    /// In-progress annotation that is updated on every `mouseDragged` and
    /// committed on `mouseUp`. Rendered alongside the committed annotations.
    private var inProgress: DrawingAnnotation?

    /// The constraint chosen at mouseDown; freehand vs. line/rect/ellipse/arrow.
    private var activeConstraint: ShapeConstraint = .freehand
    private var dragStart: CGPoint = .zero

    private var observers = Set<AnyCancellable>()

    var onExit: (() -> Void)?

    /// Black-on-white pencil cursor, hotspot at the pencil's writing tip.
    /// Composed by drawing the SF Symbol twice — once heavy/white as a halo
    /// for legibility on dark backgrounds, then once regular/black on top.
    private static let drawingCursor: NSCursor = {
        let symbolName = "pencil"
        let foreground = NSImage.SymbolConfiguration(pointSize: 18, weight: .regular)
            .applying(NSImage.SymbolConfiguration(paletteColors: [.black]))
        let halo = NSImage.SymbolConfiguration(pointSize: 18, weight: .heavy)
            .applying(NSImage.SymbolConfiguration(paletteColors: [.white]))

        guard
            let fg = NSImage(systemSymbolName: symbolName, accessibilityDescription: "Drawing pencil")?
                .withSymbolConfiguration(foreground),
            let bg = NSImage(systemSymbolName: symbolName, accessibilityDescription: nil)?
                .withSymbolConfiguration(halo)
        else {
            return .crosshair
        }

        let size = bg.size
        let composite = NSImage(size: size, flipped: false) { _ in
            bg.draw(at: .zero, from: .zero, operation: .sourceOver, fraction: 1.0)
            let inset = NSPoint(
                x: (size.width - fg.size.width) / 2,
                y: (size.height - fg.size.height) / 2
            )
            fg.draw(at: inset, from: .zero, operation: .sourceOver, fraction: 1.0)
            return true
        }

        // SF Symbol "pencil" has the writing tip at the lower-left corner.
        // NSCursor.hotSpot uses flipped (top-left origin) coordinates, so the
        // bottom-left of the image is (0, size.height - 1).
        let hotspot = NSPoint(x: 1, y: size.height - 2)
        return NSCursor(image: composite, hotSpot: hotspot)
    }()

    init(frame: NSRect, state: DrawingState) {
        self.state = state
        super.init(frame: frame)
        wantsLayer = true
        layer?.backgroundColor = NSColor.clear.cgColor

        // Redraw on any state change.
        state.objectWillChange
            .receive(on: RunLoop.main)
            .sink { [weak self] _ in self?.needsDisplay = true }
            .store(in: &observers)
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    override var acceptsFirstResponder: Bool { true }
    override var isFlipped: Bool { false }

    override func resetCursorRects() {
        addCursorRect(bounds, cursor: Self.drawingCursor)
    }

    // MARK: - Drawing

    override func draw(_ dirtyRect: NSRect) {
        guard let context = NSGraphicsContext.current?.cgContext else { return }
        context.saveGState()
        defer { context.restoreGState() }

        // Background
        switch state.background {
        case .clear:
            break // transparent — desktop shows through
        case .whiteboard, .blackboard:
            state.background.nsColor.setFill()
            bounds.fill()
        }

        for annotation in state.annotations {
            renderAnnotation(annotation, in: context)
        }
        if let inProgress {
            renderAnnotation(inProgress, in: context)
        }
    }

    private func renderAnnotation(_ annotation: DrawingAnnotation, in context: CGContext) {
        let style = annotation.style
        style.renderingColor.setStroke()
        style.renderingColor.setFill()

        let path = NSBezierPath()
        path.lineWidth = style.renderingWidth
        path.lineCapStyle = .round
        path.lineJoinStyle = .round

        switch annotation {
        case .freehand(let stroke):
            guard let first = stroke.points.first else { return }
            path.move(to: first)
            for point in stroke.points.dropFirst() {
                path.line(to: point)
            }
            path.stroke()

        case .line(let shape):
            path.move(to: shape.start)
            path.line(to: shape.end)
            path.stroke()

        case .rectangle(let shape):
            let rect = DrawingGeometry.rect(from: shape.start, to: shape.end)
            path.appendRect(rect)
            path.stroke()

        case .ellipse(let shape):
            let rect = DrawingGeometry.rect(from: shape.start, to: shape.end)
            path.appendOval(in: rect)
            path.stroke()

        case .arrow(let shape):
            path.move(to: shape.start)
            path.line(to: shape.end)
            path.stroke()
            let head = DrawingGeometry.arrowheadPath(
                from: shape.start,
                to: shape.end,
                strokeWidth: style.renderingWidth
            )
            head.fill()
        }
    }

    // MARK: - Input

    override func mouseDown(with event: NSEvent) {
        activeConstraint = ShapeConstraint.from(modifiers: event.modifierFlags)
        dragStart = convert(event.locationInWindow, from: nil)
        switch activeConstraint {
        case .freehand:
            inProgress = .freehand(FreehandStroke(style: state.currentStyle, points: [dragStart]))
        case .line:
            inProgress = .line(StraightShape(style: state.currentStyle, start: dragStart, end: dragStart))
        case .rectangle:
            inProgress = .rectangle(StraightShape(style: state.currentStyle, start: dragStart, end: dragStart))
        case .ellipse:
            inProgress = .ellipse(StraightShape(style: state.currentStyle, start: dragStart, end: dragStart))
        case .arrow:
            inProgress = .arrow(StraightShape(style: state.currentStyle, start: dragStart, end: dragStart))
        }
        needsDisplay = true
    }

    override func mouseDragged(with event: NSEvent) {
        let point = convert(event.locationInWindow, from: nil)
        switch (activeConstraint, inProgress) {
        case (.freehand, .freehand(var stroke)):
            stroke.points.append(point)
            inProgress = .freehand(stroke)
        case (.line, .line(var shape)):
            shape.end = point
            inProgress = .line(shape)
        case (.rectangle, .rectangle(var shape)):
            shape.end = point
            inProgress = .rectangle(shape)
        case (.ellipse, .ellipse(var shape)):
            shape.end = point
            inProgress = .ellipse(shape)
        case (.arrow, .arrow(var shape)):
            shape.end = point
            inProgress = .arrow(shape)
        default:
            break
        }
        needsDisplay = true
    }

    override func mouseUp(with event: NSEvent) {
        if let annotation = inProgress {
            state.commit(annotation)
        }
        inProgress = nil
        needsDisplay = true
    }

    override func rightMouseDown(with event: NSEvent) {
        onExit?()
    }

    override func keyDown(with event: NSEvent) {
        guard let characters = event.charactersIgnoringModifiers else {
            super.keyDown(with: event)
            return
        }
        let lower = characters.lowercased()
        let shiftHeld = event.modifierFlags.contains(.shift)
        let commandHeld = event.modifierFlags.contains(.command)

        // Esc exits
        if event.keyCode == 53 {
            onExit?()
            return
        }
        // Up/down adjust pen width
        if event.keyCode == 126 {
            state.adjustWidth(by: PenStyle.widthStep)
            return
        }
        if event.keyCode == 125 {
            state.adjustWidth(by: -PenStyle.widthStep)
            return
        }

        // ⌘Z undo
        if commandHeld && lower == "z" {
            state.undoLast()
            return
        }
        // E erase all
        if lower == "e" && !commandHeld {
            state.eraseAll()
            return
        }
        // W whiteboard
        if lower == "w" && !commandHeld {
            state.setBackground(.whiteboard)
            return
        }
        // K blackboard
        if lower == "k" && !commandHeld {
            state.setBackground(.blackboard)
            return
        }

        // Color shortcuts: R G B Y O P (Shift variant = highlight)
        if let firstChar = lower.first,
           let color = PenColor.allCases.first(where: { $0.shortcutCharacter == firstChar }),
           !commandHeld {
            state.setColor(color, highlight: shiftHeld)
            return
        }

        super.keyDown(with: event)
    }

    override func scrollWheel(with event: NSEvent) {
        // Ctrl+scroll adjusts pen width (matches ZoomIt's "Ctrl + Scroll" gesture).
        if event.modifierFlags.contains(.control) {
            let delta = event.scrollingDeltaY * 0.1
            state.adjustWidth(by: delta)
            return
        }
        super.scrollWheel(with: event)
    }
}
