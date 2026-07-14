import AppKit
import Combine
import CoreImage

/// NSView that renders committed annotations, the frozen-screen background
/// (when present), captures mouse input for new strokes/shapes/text, and
/// routes keyboard shortcuts to its `DrawingState`.
final class DrawingCanvas: NSView {
    let state: DrawingState

    /// Frozen screen image captured at activation. When non-nil it is rendered
    /// as the bottom layer of the canvas (ZoomIt-style "freeze on Draw").
    private let frozenBackground: CGImage?
    private let backingScale: CGFloat

    /// Pre-blurred copy of `frozenBackground`, lazily generated on first use.
    private var blurredBackground: CGImage?

    /// In-progress freehand stroke / shape (ink tool).
    private var inProgressInk: DrawingAnnotation?

    /// In-progress blur rect (being click-and-dragged).
    private var inProgressBlur: BlurArea?

    /// The shape constraint chosen at mouseDown for ink strokes.
    private var activeConstraint: ShapeConstraint = .freehand
    private var dragStart: CGPoint = .zero

    /// Visibility of the caret in text-entry mode — toggled by `caretTimer`.
    private var caretVisible: Bool = true
    private var caretTimer: Timer?

    private var observers = Set<AnyCancellable>()

    /// Whether the "press H" shortcuts hub overlay is currently shown.
    private var hubVisible: Bool = false

    var onExit: (() -> Void)?

    /// Black-on-white pencil cursor, hotspot at the pencil's writing tip.
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

        let hotspot = NSPoint(x: 1, y: size.height - 2)
        return NSCursor(image: composite, hotSpot: hotspot)
    }()

    init(
        frame: NSRect,
        state: DrawingState,
        frozenBackground: CGImage? = nil,
        backingScale: CGFloat = 2.0
    ) {
        self.state = state
        self.frozenBackground = frozenBackground
        self.backingScale = backingScale
        super.init(frame: frame)
        wantsLayer = true
        layer?.backgroundColor = NSColor.clear.cgColor

        // Redraw on any state change.
        state.objectWillChange
            .receive(on: RunLoop.main)
            .sink { [weak self] _ in
                self?.needsDisplay = true
                self?.updateCaretTimer()
            }
            .store(in: &observers)
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    deinit {
        caretTimer?.invalidate()
    }

    override var acceptsFirstResponder: Bool { true }
    override var isFlipped: Bool { false }

    override func resetCursorRects() {
        let cursor: NSCursor
        switch state.currentTool {
        case .ink:  cursor = Self.drawingCursor
        case .blur: cursor = .crosshair
        case .text: cursor = .iBeam
        }
        addCursorRect(bounds, cursor: cursor)
    }

    // MARK: - Drawing

    override func draw(_ dirtyRect: NSRect) {
        guard let context = NSGraphicsContext.current?.cgContext else { return }
        context.saveGState()
        defer { context.restoreGState() }

        // Background fill / frozen image.
        switch state.background {
        case .clear:
            if let frozenBackground {
                context.draw(frozenBackground, in: bounds)
            }
            // No frozen image and clear background -> transparent overlay
            // (legacy LiveDraw fallback when capture is denied).
        case .whiteboard, .blackboard:
            state.background.nsColor.setFill()
            bounds.fill()
        }

        for annotation in state.annotations {
            renderAnnotation(annotation, in: context)
        }
        if let ink = inProgressInk {
            renderAnnotation(ink, in: context)
        }
        if let blur = inProgressBlur {
            renderBlurArea(blur, in: context, showOutline: true)
        }
        if let draft = state.inProgressText {
            renderTextDraft(draft, in: context)
        }

        if hubVisible {
            drawHub(in: context)
        }
    }

    private func renderAnnotation(_ annotation: DrawingAnnotation, in context: CGContext) {
        switch annotation {
        case .blur(let area):
            renderBlurArea(area, in: context, showOutline: false)
            return
        case .text(let stamp):
            renderTextStamp(stamp, caretVisible: false, isCommitted: true)
            return
        default:
            break
        }

        guard let style = annotation.style else { return }
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

        case .blur, .text:
            return
        }
    }

    private func renderBlurArea(_ area: BlurArea, in context: CGContext, showOutline: Bool) {
        let rect = area.rect.standardized
        guard rect.width > 0 && rect.height > 0 else { return }

        context.saveGState()
        defer { context.restoreGState() }
        context.addRect(rect)
        context.clip()

        if let blurred = ensureBlurredBackground() {
            // Proper gaussian blur of the frozen-screen background, clipped
            // to the user-selected rectangle.
            context.draw(blurred, in: bounds)
        } else {
            // No frozen background (screen-recording denied, or live-draw
            // overlay) — fall back to an opaque redaction so the blur tool
            // is still useful as a privacy mask.
            context.setFillColor(NSColor.black.withAlphaComponent(0.92).cgColor)
            context.fill(rect)
        }

        if showOutline {
            // Thin dashed outline during the drag so the selection is clear
            // even when the underlying area is busy. `clip()` above limits
            // drawing to the rect interior, so we need a fresh state to draw
            // the outline on top.
            context.restoreGState()
            context.saveGState()
            context.setStrokeColor(NSColor.white.withAlphaComponent(0.95).cgColor)
            context.setLineWidth(1.0)
            context.setLineDash(phase: 0, lengths: [4, 3])
            context.stroke(rect)
        }
    }

    /// Lazily produces a Gaussian-blurred copy of `frozenBackground` for blur
    /// strokes to clip against. Returns nil if there's no frozen image.
    private func ensureBlurredBackground() -> CGImage? {
        if let cached = blurredBackground { return cached }
        guard let source = frozenBackground else { return nil }
        let ciContext = CIContext(options: nil)
        let input = CIImage(cgImage: source)
        let filter = CIFilter(name: "CIGaussianBlur")
        filter?.setValue(input, forKey: kCIInputImageKey)
        filter?.setValue(24.0, forKey: kCIInputRadiusKey)
        guard let output = filter?.outputImage else { return nil }
        // Clamp the output extent to the source's extent so blur doesn't
        // shrink the image by 2*radius on each edge.
        let cropped = output.cropped(to: input.extent)
        guard let result = ciContext.createCGImage(cropped, from: input.extent) else { return nil }
        blurredBackground = result
        return result
    }

    private func renderTextStamp(_ stamp: TextStamp, caretVisible: Bool, isCommitted: Bool) {
        let attributes: [NSAttributedString.Key: Any] = [
            .font: NSFont.systemFont(ofSize: stamp.fontSize, weight: .semibold),
            .foregroundColor: stamp.style.renderingColor,
        ]
        let string = NSAttributedString(string: stamp.text, attributes: attributes)
        string.draw(at: stamp.origin)

        if !isCommitted {
            // Caret indicator: a thin vertical bar at the right edge of the text.
            let textWidth = string.size().width
            let caretRect = NSRect(
                x: stamp.origin.x + textWidth + 1,
                y: stamp.origin.y,
                width: max(1, stamp.fontSize / 18),
                height: stamp.fontSize * 1.1
            )
            if caretVisible {
                stamp.style.renderingColor.setFill()
                caretRect.fill()
            }
            // Selection underline so the user can see where the caret is
            // even when the caret blink is off and the text is empty.
            if stamp.text.isEmpty {
                let underline = NSRect(
                    x: stamp.origin.x - 2,
                    y: stamp.origin.y - 4,
                    width: max(12, stamp.fontSize * 0.5),
                    height: 1
                )
                stamp.style.renderingColor.withAlphaComponent(0.6).setFill()
                underline.fill()
            }
        }
    }

    private func renderTextDraft(_ draft: TextStamp, in context: CGContext) {
        renderTextStamp(draft, caretVisible: caretVisible, isCommitted: false)
    }

    // MARK: - Shortcuts hub overlay

    /// A single labelled key/option "chip" inside the hub.
    private struct HubChip {
        let key: String
        let label: String
        let active: Bool
        let swatch: NSColor?

        init(key: String, label: String, active: Bool = false, swatch: NSColor? = nil) {
            self.key = key
            self.label = label
            self.active = active
            self.swatch = swatch
        }
    }

    /// A titled group of chips.
    private struct HubSection {
        let title: String
        let chips: [HubChip]
    }

    // Layout constants for the hub.
    private static let hubPanelWidth: CGFloat = 640
    private static let hubSidePad: CGFloat = 24
    private static let hubTopPad: CGFloat = 22
    private static let hubBottomPad: CGFloat = 22
    private static let hubChipHeight: CGFloat = 32
    private static let hubChipHGap: CGFloat = 8
    private static let hubChipVGap: CGFloat = 8
    private static let hubSectionGap: CGFloat = 18
    private static let hubSectionTitleGap: CGFloat = 8
    private static let hubHeaderGap: CGFloat = 16
    private static let hubChipPadX: CGFloat = 12
    private static let hubSwatchSize: CGFloat = 12
    private static let hubSwatchGap: CGFloat = 8
    private static let hubKeyLabelGap: CGFloat = 8

    private static let hubKeyFont = NSFont.monospacedSystemFont(ofSize: 12, weight: .bold)
    private static let hubLabelFont = NSFont.systemFont(ofSize: 13, weight: .regular)
    private static let hubSectionTitleFont = NSFont.systemFont(ofSize: 11, weight: .semibold)
    private static let hubHeaderFont = NSFont.systemFont(ofSize: 17, weight: .bold)
    private static let hubFooterFont = NSFont.systemFont(ofSize: 11, weight: .regular)
    private static let hubAccent = NSColor(srgbRed: 0.35, green: 0.62, blue: 1.0, alpha: 1.0)

    private func hubSections() -> [HubSection] {
        let tool = state.currentTool
        let bg = state.background
        let color = state.currentColor
        let inkActive = tool == .ink

        let colorChips = PenColor.allCases.map { c in
            HubChip(
                key: String(c.shortcutCharacter).uppercased(),
                label: c.displayName,
                active: inkActive && color == c,
                swatch: c.nsColor
            )
        }

        return [
            HubSection(title: "TOOLS", chips: [
                HubChip(key: "I", label: "Pen", active: tool == .ink),
                HubChip(key: "B", label: "Blur", active: tool == .blur),
                HubChip(key: "T", label: "Text", active: tool == .text),
            ]),
            HubSection(title: "COLORS   ·   hold ⇧ for highlight", chips: colorChips),
            HubSection(title: "CANVAS", chips: [
                HubChip(key: "W", label: "Whiteboard", active: bg == .whiteboard),
                HubChip(key: "K", label: "Blackboard", active: bg == .blackboard),
                HubChip(key: "E", label: "Erase all"),
            ]),
            HubSection(title: "SHAPES   ·   hold a modifier while dragging", chips: [
                HubChip(key: "—", label: "Freehand"),
                HubChip(key: "⇧", label: "Line"),
                HubChip(key: "⌥", label: "Rectangle"),
                HubChip(key: "⌃", label: "Ellipse"),
                HubChip(key: "⇧⌥", label: "Arrow"),
            ]),
            HubSection(title: "SIZE & EDIT", chips: [
                HubChip(key: "↑↓", label: "Width \(Int(state.currentWidth.rounded())) px"),
                HubChip(key: "⌃scroll", label: "Width"),
                HubChip(key: "⌘Z", label: "Undo"),
                HubChip(key: "Esc", label: "Exit"),
            ]),
        ]
    }

    private func hubChipWidth(_ chip: HubChip) -> CGFloat {
        var w = Self.hubChipPadX * 2
        if chip.swatch != nil {
            w += Self.hubSwatchSize + Self.hubSwatchGap
        }
        if !chip.key.isEmpty {
            let keySize = (chip.key as NSString).size(withAttributes: [.font: Self.hubKeyFont])
            w += keySize.width + Self.hubKeyLabelGap
        }
        let labelSize = (chip.label as NSString).size(withAttributes: [.font: Self.hubLabelFont])
        w += labelSize.width
        return w
    }

    /// Wraps a section's chips into visual rows that fit `contentWidth`.
    private func hubRows(for chips: [HubChip], contentWidth: CGFloat) -> [[HubChip]] {
        var rows: [[HubChip]] = []
        var current: [HubChip] = []
        var currentWidth: CGFloat = 0
        for chip in chips {
            let w = hubChipWidth(chip)
            if current.isEmpty {
                current = [chip]
                currentWidth = w
            } else if currentWidth + Self.hubChipHGap + w <= contentWidth {
                current.append(chip)
                currentWidth += Self.hubChipHGap + w
            } else {
                rows.append(current)
                current = [chip]
                currentWidth = w
            }
        }
        if !current.isEmpty { rows.append(current) }
        return rows
    }

    private func drawHub(in context: CGContext) {
        let sections = hubSections()
        let contentWidth = Self.hubPanelWidth - Self.hubSidePad * 2

        // Pre-wrap every section so we know the panel height before drawing.
        let laidOut: [(title: String, rows: [[HubChip]])] = sections.map {
            ($0.title, hubRows(for: $0.chips, contentWidth: contentWidth))
        }

        let headerHeight = (Self.hubHeaderFont.ascender - Self.hubHeaderFont.descender)
        let sectionTitleHeight = (Self.hubSectionTitleFont.ascender - Self.hubSectionTitleFont.descender)
        let footerHeight = (Self.hubFooterFont.ascender - Self.hubFooterFont.descender)

        var panelHeight = Self.hubTopPad + Self.hubBottomPad
        panelHeight += headerHeight + Self.hubHeaderGap
        for section in laidOut {
            panelHeight += sectionTitleHeight + Self.hubSectionTitleGap
            let rowCount = CGFloat(section.rows.count)
            panelHeight += rowCount * Self.hubChipHeight
            panelHeight += max(0, rowCount - 1) * Self.hubChipVGap
            panelHeight += Self.hubSectionGap
        }
        panelHeight += footerHeight // footer hint line

        let panelRect = NSRect(
            x: (bounds.width - Self.hubPanelWidth) / 2,
            y: (bounds.height - panelHeight) / 2,
            width: Self.hubPanelWidth,
            height: panelHeight
        )

        // Dim the whole screen slightly so the hub reads clearly over any
        // background (frozen screen, whiteboard, or busy drawings).
        context.saveGState()
        context.setFillColor(NSColor.black.withAlphaComponent(0.28).cgColor)
        context.fill(bounds)
        context.restoreGState()

        // Panel background + border.
        let panelPath = NSBezierPath(roundedRect: panelRect, xRadius: 18, yRadius: 18)
        NSColor(white: 0.10, alpha: 0.95).setFill()
        panelPath.fill()
        NSColor(white: 1.0, alpha: 0.12).setStroke()
        panelPath.lineWidth = 1
        panelPath.stroke()

        let leftX = panelRect.minX + Self.hubSidePad
        var topY = panelRect.maxY - Self.hubTopPad

        // Header.
        drawHubText("Drawing shortcuts", font: Self.hubHeaderFont,
                    color: .white, x: leftX, topY: topY)
        topY -= headerHeight + Self.hubHeaderGap

        for section in laidOut {
            drawHubText(section.title, font: Self.hubSectionTitleFont,
                        color: NSColor(white: 0.62, alpha: 1.0), x: leftX, topY: topY)
            topY -= sectionTitleHeight + Self.hubSectionTitleGap

            for row in section.rows {
                var x = leftX
                for chip in row {
                    let w = hubChipWidth(chip)
                    let chipRect = NSRect(x: x, y: topY - Self.hubChipHeight,
                                          width: w, height: Self.hubChipHeight)
                    drawHubChip(chip, in: chipRect)
                    x += w + Self.hubChipHGap
                }
                topY -= Self.hubChipHeight + Self.hubChipVGap
            }
            topY += Self.hubChipVGap // last row has no trailing gap
            topY -= Self.hubSectionGap
        }

        // Footer hint, right-aligned.
        let footer = "H or Esc to close"
        let footerSize = (footer as NSString).size(withAttributes: [.font: Self.hubFooterFont])
        drawHubText(footer, font: Self.hubFooterFont,
                    color: NSColor(white: 0.5, alpha: 1.0),
                    x: panelRect.maxX - Self.hubSidePad - footerSize.width,
                    topY: panelRect.minY + Self.hubBottomPad + footerHeight)
    }

    private func drawHubChip(_ chip: HubChip, in rect: NSRect) {
        let path = NSBezierPath(roundedRect: rect, xRadius: 8, yRadius: 8)
        if chip.active {
            NSColor(white: 1.0, alpha: 0.16).setFill()
            path.fill()
            Self.hubAccent.setStroke()
            path.lineWidth = 1.5
            path.stroke()
        } else {
            NSColor(white: 1.0, alpha: 0.07).setFill()
            path.fill()
        }

        var x = rect.minX + Self.hubChipPadX

        if let swatch = chip.swatch {
            let dot = NSRect(x: x, y: rect.midY - Self.hubSwatchSize / 2,
                             width: Self.hubSwatchSize, height: Self.hubSwatchSize)
            swatch.setFill()
            NSBezierPath(ovalIn: dot).fill()
            NSColor(white: 1.0, alpha: 0.35).setStroke()
            let ring = NSBezierPath(ovalIn: dot)
            ring.lineWidth = 0.5
            ring.stroke()
            x += Self.hubSwatchSize + Self.hubSwatchGap
        }

        if !chip.key.isEmpty {
            let keyColor = chip.active ? Self.hubAccent : NSColor(white: 0.95, alpha: 1.0)
            let keyAttrs: [NSAttributedString.Key: Any] = [
                .font: Self.hubKeyFont, .foregroundColor: keyColor,
            ]
            let keyStr = NSAttributedString(string: chip.key, attributes: keyAttrs)
            let keySize = keyStr.size()
            keyStr.draw(at: NSPoint(x: x, y: rect.midY - keySize.height / 2))
            x += keySize.width + Self.hubKeyLabelGap
        }

        let labelAttrs: [NSAttributedString.Key: Any] = [
            .font: Self.hubLabelFont,
            .foregroundColor: NSColor(white: 0.88, alpha: 1.0),
        ]
        let labelStr = NSAttributedString(string: chip.label, attributes: labelAttrs)
        let labelSize = labelStr.size()
        labelStr.draw(at: NSPoint(x: x, y: rect.midY - labelSize.height / 2))
    }

    /// Draws a single line of text whose visual top sits at `topY`.
    private func drawHubText(_ text: String, font: NSFont, color: NSColor, x: CGFloat, topY: CGFloat) {
        let attrs: [NSAttributedString.Key: Any] = [.font: font, .foregroundColor: color]
        let str = NSAttributedString(string: text, attributes: attrs)
        let size = str.size()
        str.draw(at: NSPoint(x: x, y: topY - size.height))
    }



    private func updateCaretTimer() {
        let needsTimer = (state.inProgressText != nil)
        if needsTimer && caretTimer == nil {
            caretVisible = true
            caretTimer = Timer.scheduledTimer(withTimeInterval: 0.5, repeats: true) { [weak self] _ in
                Task { @MainActor [weak self] in
                    guard let self else { return }
                    self.caretVisible.toggle()
                    self.needsDisplay = true
                }
            }
        } else if !needsTimer && caretTimer != nil {
            caretTimer?.invalidate()
            caretTimer = nil
            caretVisible = true
        }
    }

    // MARK: - Input

    override func mouseDown(with event: NSEvent) {
        // A click while the shortcuts hub is open just dismisses it; it must
        // not start a stroke underneath the overlay.
        if hubVisible {
            hubVisible = false
            needsDisplay = true
            return
        }

        let point = convert(event.locationInWindow, from: nil)
        dragStart = point

        switch state.currentTool {
        case .text:
            // Click while another text draft is active commits the old one,
            // then begins a fresh draft at the click location.
            state.commitInProgressText()
            state.beginText(at: point)
            needsDisplay = true
            return

        case .blur:
            // Click-and-drag selects a rectangular area to blur. We
            // initialize both corners at the click point and update the
            // opposite corner on drag.
            inProgressBlur = BlurArea(rect: CGRect(origin: point, size: .zero))

        case .ink:
            activeConstraint = ShapeConstraint.from(modifiers: event.modifierFlags)
            switch activeConstraint {
            case .freehand:
                inProgressInk = .freehand(FreehandStroke(style: state.currentStyle, points: [point]))
            case .line:
                inProgressInk = .line(StraightShape(style: state.currentStyle, start: point, end: point))
            case .rectangle:
                inProgressInk = .rectangle(StraightShape(style: state.currentStyle, start: point, end: point))
            case .ellipse:
                inProgressInk = .ellipse(StraightShape(style: state.currentStyle, start: point, end: point))
            case .arrow:
                inProgressInk = .arrow(StraightShape(style: state.currentStyle, start: point, end: point))
            }
        }
        needsDisplay = true
    }

    override func mouseDragged(with event: NSEvent) {
        let point = convert(event.locationInWindow, from: nil)

        switch state.currentTool {
        case .text:
            return // Drag in text mode is a no-op
        case .blur:
            // Drag updates the rect from the original press location
            // (`dragStart`) to the current cursor.
            inProgressBlur?.rect = DrawingGeometry.rect(from: dragStart, to: point)
        case .ink:
            switch (activeConstraint, inProgressInk) {
            case (.freehand, .freehand(var stroke)):
                stroke.points.append(point)
                inProgressInk = .freehand(stroke)
            case (.line, .line(var shape)):
                shape.end = point
                inProgressInk = .line(shape)
            case (.rectangle, .rectangle(var shape)):
                shape.end = point
                inProgressInk = .rectangle(shape)
            case (.ellipse, .ellipse(var shape)):
                shape.end = point
                inProgressInk = .ellipse(shape)
            case (.arrow, .arrow(var shape)):
                shape.end = point
                inProgressInk = .arrow(shape)
            default:
                break
            }
        }
        needsDisplay = true
    }

    override func mouseUp(with event: NSEvent) {
        switch state.currentTool {
        case .text:
            break
        case .blur:
            // Commit only if the user actually dragged out a non-degenerate
            // rectangle; a stray click shouldn't leave a 1px blur artifact.
            if let area = inProgressBlur,
               area.rect.width >= 2,
               area.rect.height >= 2 {
                state.commit(.blur(area))
            }
            inProgressBlur = nil
        case .ink:
            if let annotation = inProgressInk {
                state.commit(annotation)
            }
            inProgressInk = nil
        }
        needsDisplay = true
    }

    override func rightMouseDown(with event: NSEvent) {
        // Right-click commits any in-progress text, otherwise exits.
        if state.inProgressText != nil {
            state.commitInProgressText()
            needsDisplay = true
        } else {
            onExit?()
        }
    }

    override func keyDown(with event: NSEvent) {
        // Text-entry mode: capture everything that's a printable character
        // or text-editing key. Tool/color/background shortcuts are suppressed.
        if state.inProgressText != nil {
            handleTextInput(event)
            return
        }

        guard let characters = event.charactersIgnoringModifiers else {
            super.keyDown(with: event)
            return
        }
        let lower = characters.lowercased()
        let shiftHeld = event.modifierFlags.contains(.shift)
        let commandHeld = event.modifierFlags.contains(.command)

        // Esc exits draw mode (when no in-progress text). If the shortcuts hub
        // is open, Esc closes it first instead of tearing down draw mode.
        if event.keyCode == 53 {
            if hubVisible {
                hubVisible = false
                needsDisplay = true
                return
            }
            onExit?()
            return
        }
        // Up/down arrows adjust pen width.
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

        // H toggles the shortcuts hub overlay (a legend of every drawing
        // option). Only active outside text entry — inside text entry "h" is
        // a literal character (handled above).
        if lower == "h" && !commandHeld {
            hubVisible.toggle()
            needsDisplay = true
            return
        }

        // Tool-switching shortcuts. These take precedence over color/background
        // letters with the same key (T overrides nothing; B / I are also color
        // letters — we map them as TOOLS first since users press color keys
        // far more often while in ink mode and we always want tool switches
        // to be unambiguous). Shift+B/I still selects the color so the
        // highlight-blue and "indigo" use cases remain reachable.
        if !commandHeld && !shiftHeld {
            if lower == "t" { state.setTool(.text);  return }
            if lower == "i" { state.setTool(.ink);   return }
            if lower == "b" { state.setTool(.blur);  return }
        }

        // E erase all (and reset to .clear background).
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

        // Color shortcuts: R G B Y O P (Shift variant = highlight).
        // `B` is normally consumed by the blur-tool shortcut above; Shift+B
        // still routes here so the user can pick highlight-blue.
        //
        // We also force-switch back to `.ink` here so that pressing a color
        // key while the Blur tool is active gives visible feedback — without
        // this, the color is updated silently but the blur tool ignores it,
        // which previously left users stuck in Blur after pressing `B`.
        if let firstChar = lower.first,
           let color = PenColor.allCases.first(where: { $0.shortcutCharacter == firstChar }),
           !commandHeld {
            state.setColor(color, highlight: shiftHeld)
            state.setTool(.ink)
            return
        }

        super.keyDown(with: event)
    }

    private func handleTextInput(_ event: NSEvent) {
        let keyCode = event.keyCode

        switch keyCode {
        case 53: // Esc -> cancel current text without committing
            state.cancelInProgressText()
            needsDisplay = true
            return
        case 36, 76: // Return / Enter -> commit
            state.commitInProgressText()
            needsDisplay = true
            return
        case 51: // Delete (Backspace)
            state.deleteBackwardInText()
            needsDisplay = true
            return
        case 126: // Up arrow -> bigger font
            state.adjustTextFontSize(by: DrawingState.textFontStep)
            needsDisplay = true
            return
        case 125: // Down arrow -> smaller font
            state.adjustTextFontSize(by: -DrawingState.textFontStep)
            needsDisplay = true
            return
        default:
            break
        }

        // Treat anything else with printable characters as input. Strip
        // non-printable control chars produced by Cmd/Option chords.
        if event.modifierFlags.contains(.command) {
            // Cmd+anything: ignore; don't dirty the text.
            return
        }
        if let chars = event.characters, !chars.isEmpty {
            // Filter out function keys, etc.
            let filtered = chars.filter { ch in
                guard let scalar = ch.unicodeScalars.first else { return false }
                if scalar.value < 0x20 { return false }      // control chars
                if scalar.value == 0x7F { return false }     // delete
                if scalar.value >= 0xF700 && scalar.value <= 0xF8FF { return false } // function keys
                return true
            }
            if !filtered.isEmpty {
                state.appendText(filtered)
                needsDisplay = true
            }
        }
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

private extension NSBezierPath {
    /// CGPath equivalent of the receiver. NSBezierPath doesn't ship one on
    /// older SDKs and the conversion is a few lines, so we keep it local.
    var cgPath: CGPath {
        let path = CGMutablePath()
        var points = [NSPoint](repeating: .zero, count: 3)
        for i in 0..<elementCount {
            let type = element(at: i, associatedPoints: &points)
            switch type {
            case .moveTo:
                path.move(to: points[0])
            case .lineTo:
                path.addLine(to: points[0])
            case .curveTo, .cubicCurveTo:
                path.addCurve(to: points[2], control1: points[0], control2: points[1])
            case .quadraticCurveTo:
                path.addQuadCurve(to: points[1], control: points[0])
            case .closePath:
                path.closeSubpath()
            @unknown default:
                break
            }
        }
        return path
    }
}
