import AppKit
import QuartzCore

/// The rendering surface inside a `ZoomWindow`. Owns the captured image
/// (as a `CALayer.contents`) and applies pan + zoom transformations as the
/// user interacts with it.
final class ZoomView: NSView {
    private let imageLayer = CALayer()

    private(set) var zoomLevel: CGFloat = 2.0
    private var sourceImage: CGImage?
    /// Size of the source image in points (i.e. pixels / backingScale).
    private var sourcePointSize: CGSize = .zero
    /// The source point that we want anchored at `focalScreen`.
    private var focalSource: CGPoint = .zero
    /// Where on screen the focal source point appears. Set from mouse position.
    private var focalScreen: CGPoint = .zero

    var smoothing: Bool = true {
        didSet { applyMagnificationFilter() }
    }

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        configureLayers()
    }

    required init?(coder: NSCoder) {
        super.init(coder: coder)
        configureLayers()
    }

    private func configureLayers() {
        wantsLayer = true
        layer = CALayer()
        layer?.backgroundColor = NSColor.black.cgColor
        imageLayer.anchorPoint = .zero
        imageLayer.contentsGravity = .resize
        layer?.addSublayer(imageLayer)
        applyMagnificationFilter()
    }

    private func applyMagnificationFilter() {
        imageLayer.magnificationFilter = smoothing ? .linear : .nearest
    }

    override var acceptsFirstResponder: Bool { true }
    override var isFlipped: Bool { false }

    // MARK: - Public API

    func configure(image: CGImage, backingScale: CGFloat, initialZoom: CGFloat, focalScreen: CGPoint) {
        self.sourceImage = image
        self.sourcePointSize = CGSize(
            width: CGFloat(image.width) / backingScale,
            height: CGFloat(image.height) / backingScale
        )
        imageLayer.contents = image
        // The focal source point at activation = the screen point under the cursor.
        // In native (non-zoomed) coordinates, that's just the screen point itself,
        // since at zoom 1.0 the image fills the screen 1:1.
        self.focalSource = focalScreen
        self.focalScreen = focalScreen
        self.zoomLevel = ZoomGeometry.clamp(level: initialZoom)
        applyLayout(animated: false)
    }

    func updateFocalScreen(_ screenPoint: CGPoint) {
        // The same source point should stay under the cursor as it moves.
        // i.e. recompute focalSource from the new screen position so that the
        // image effectively pans.
        let newSource = ZoomGeometry.sourcePoint(
            forScreenPoint: screenPoint,
            zoomLevel: zoomLevel,
            focalSource: focalSource,
            focalScreen: focalScreen
        )
        focalScreen = screenPoint
        focalSource = ZoomGeometry.clampFocalSource(
            newSource,
            zoomLevel: zoomLevel,
            sourcePointSize: sourcePointSize,
            destinationSize: bounds.size,
            focalScreen: focalScreen
        )
        applyLayout(animated: false)
    }

    func adjustZoom(by delta: CGFloat) {
        let newLevel = ZoomGeometry.clamp(level: zoomLevel + delta)
        guard newLevel != zoomLevel else { return }
        zoomLevel = newLevel
        focalSource = ZoomGeometry.clampFocalSource(
            focalSource,
            zoomLevel: zoomLevel,
            sourcePointSize: sourcePointSize,
            destinationSize: bounds.size,
            focalScreen: focalScreen
        )
        applyLayout(animated: false)
    }

    func performZoomInAnimation(from startLevel: CGFloat = 1.0) {
        let target = zoomLevel
        zoomLevel = startLevel
        applyLayout(animated: false)
        CATransaction.begin()
        CATransaction.setAnimationDuration(0.18)
        CATransaction.setAnimationTimingFunction(CAMediaTimingFunction(name: .easeOut))
        zoomLevel = target
        applyLayout(animated: true)
        CATransaction.commit()
    }

    func performZoomOutAnimation(completion: @escaping () -> Void) {
        CATransaction.begin()
        CATransaction.setAnimationDuration(0.16)
        CATransaction.setAnimationTimingFunction(CAMediaTimingFunction(name: .easeIn))
        CATransaction.setCompletionBlock(completion)
        zoomLevel = ZoomGeometry.minLevel
        applyLayout(animated: true)
        CATransaction.commit()
    }

    /// Render the currently displayed zoomed view to a CGImage. Used by the
    /// Zoom→Draw handoff: the resulting bitmap becomes Draw mode's frozen
    /// background, so annotations land on top of the zoomed-in view rather
    /// than the original unzoomed screen capture.
    func renderCurrentView() -> CGImage? {
        guard let rep = bitmapImageRepForCachingDisplay(in: bounds) else { return nil }
        cacheDisplay(in: bounds, to: rep)
        return rep.cgImage
    }

    // MARK: - Layout

    override func layout() {
        super.layout()
        applyLayout(animated: false)
    }

    private func applyLayout(animated: Bool) {
        guard sourceImage != nil else { return }
        if !animated {
            CATransaction.begin()
            CATransaction.setDisableActions(true)
        }
        imageLayer.frame = ZoomGeometry.imageLayerFrame(
            sourcePointSize: sourcePointSize,
            zoomLevel: zoomLevel,
            focalSource: focalSource,
            focalScreen: focalScreen
        )
        if !animated {
            CATransaction.commit()
        }
    }
}
