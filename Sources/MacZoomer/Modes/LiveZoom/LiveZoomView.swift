import AppKit
import AVFoundation
import QuartzCore

/// Live-feed counterpart to `ZoomView`. Renders `CMSampleBuffer` frames from
/// `LiveScreenCapturer` via `AVSampleBufferDisplayLayer` and applies the same
/// pan/zoom math (`ZoomGeometry`) as the static zoom view.
///
/// The display layer is the size of the (zoomed) source in destination
/// coordinates, positioned so the desired source point sits under the
/// requested screen point — identical to `ZoomView`'s `imageLayer.frame`.
final class LiveZoomView: NSView {
    private let videoLayer = AVSampleBufferDisplayLayer()

    private(set) var zoomLevel: CGFloat = 2.0
    private var sourcePointSize: CGSize = .zero
    private var focalSource: CGPoint = .zero
    private var focalScreen: CGPoint = .zero

    /// Toggles between nearest-neighbour and linear sampling.
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
        videoLayer.anchorPoint = .zero
        videoLayer.videoGravity = .resize
        layer?.addSublayer(videoLayer)
        applyMagnificationFilter()
    }

    private func applyMagnificationFilter() {
        videoLayer.magnificationFilter = smoothing ? .linear : .nearest
    }

    override var acceptsFirstResponder: Bool { true }
    override var isFlipped: Bool { false }

    // MARK: - Public API

    /// Establish the source size and focal point. Call before frames begin
    /// arriving so the layer is positioned correctly for the very first frame.
    func configure(sourcePointSize: CGSize, initialZoom: CGFloat, focalScreen: CGPoint) {
        self.sourcePointSize = sourcePointSize
        self.focalSource = focalScreen
        self.focalScreen = focalScreen
        self.zoomLevel = ZoomGeometry.clamp(level: initialZoom)
        applyLayout(animated: false)
    }

    /// Enqueue the latest captured frame for display.
    ///
    /// Called from the SCStream output queue — `AVSampleBufferDisplayLayer`
    /// is thread-safe so we don't need to hop to main.
    func enqueueFrame(_ sampleBuffer: CMSampleBuffer) {
        // Mark for immediate display so the layer doesn't hold frames in its
        // internal queue waiting for their PTS — we want the latest frame
        // shown as soon as possible.
        if let attachments = CMSampleBufferGetSampleAttachmentsArray(sampleBuffer, createIfNecessary: true) as NSArray?,
           attachments.count > 0,
           let attachment = attachments[0] as? NSMutableDictionary {
            attachment[kCMSampleAttachmentKey_DisplayImmediately as NSString] = true
        }

        guard videoLayer.status != .failed else {
            videoLayer.flush()
            return
        }
        if videoLayer.isReadyForMoreMediaData {
            videoLayer.enqueue(sampleBuffer)
        }
    }

    func updateFocalScreen(_ screenPoint: CGPoint) {
        // ZoomIt-style cursor-tracking pan: the source pixel at the
        // cursor's desktop position should appear at the cursor's screen
        // position inside the magnified view. Our source is the display
        // captured 1:1, so source pixel == screen pixel and we set
        // focalSource = focalScreen directly. `clampFocalSource` keeps
        // the magnified view inside the source so the screen never
        // shows uncovered black bars near edges.
        focalScreen = screenPoint
        focalSource = ZoomGeometry.clampFocalSource(
            screenPoint,
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

    /// Snapshot the current live-zoom view for the Live Zoom → Draw handoff.
    /// We sample the layer-backed view via `cacheDisplay(in:to:)`, identical
    /// to `ZoomView.renderCurrentView()`.
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
        guard sourcePointSize != .zero else { return }
        if !animated {
            CATransaction.begin()
            CATransaction.setDisableActions(true)
        }
        videoLayer.frame = ZoomGeometry.imageLayerFrame(
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
