import AppKit
import CoreMedia
import ScreenCaptureKit

/// One running SCStream for a single display, delivering frames to a callback.
///
/// `LiveZoomMode` owns one instance per display. Frames arrive on a private
/// serial queue (`outputQueue`) and the consumer is responsible for marshalling
/// to whichever thread it needs — `AVSampleBufferDisplayLayer.enqueue(_:)`
/// is thread-safe so we don't trampoline to main for rendering.
public final class LiveScreenCapturer: NSObject, SCStreamOutput, SCStreamDelegate, @unchecked Sendable {
    public typealias FrameHandler = @Sendable (CMSampleBuffer) -> Void

    private var stream: SCStream?
    private var frameHandler: FrameHandler?
    private let outputQueue = DispatchQueue(label: "com.markusbosch.MacZoomer.liveCapture", qos: .userInteractive)

    public override init() {}

    /// Begin streaming the given display at the requested point size, excluding
    /// the host process's own windows so the magnified view doesn't capture
    /// itself (which would feedback-loop into runaway recursion).
    ///
    /// `targetFPS` clamps frame delivery — 60 by default is plenty for live
    /// magnification and keeps GPU load reasonable.
    public func start(
        display: SCDisplay,
        targetFPS: Int = 60,
        showsCursor: Bool = true,
        onFrame: @escaping FrameHandler
    ) async throws {
        // Find our own SCRunningApplication so we can exclude it from capture.
        let content = try await SCShareableContent.excludingDesktopWindows(
            false,
            onScreenWindowsOnly: true
        )
        let ownPID = ProcessInfo.processInfo.processIdentifier
        let ownApps = content.applications.filter { $0.processID == ownPID }

        let filter = SCContentFilter(
            display: display,
            excludingApplications: ownApps,
            exceptingWindows: []
        )

        let config = SCStreamConfiguration()
        config.width = Int(display.width)
        config.height = Int(display.height)
        config.minimumFrameInterval = CMTime(value: 1, timescale: CMTimeScale(targetFPS))
        config.queueDepth = 5
        config.showsCursor = showsCursor
        config.pixelFormat = kCVPixelFormatType_32BGRA
        config.colorSpaceName = CGColorSpace.sRGB

        let stream = SCStream(filter: filter, configuration: config, delegate: self)
        try stream.addStreamOutput(self, type: .screen, sampleHandlerQueue: outputQueue)

        self.frameHandler = onFrame
        self.stream = stream

        try await stream.startCapture()
    }

    public func stop() async {
        guard let stream = stream else { return }
        self.stream = nil
        self.frameHandler = nil
        do {
            try await stream.stopCapture()
        } catch {
            NSLog("MacZoomer: SCStream stop failed: \(error)")
        }
    }

    // MARK: - SCStreamOutput

    public func stream(_ stream: SCStream, didOutputSampleBuffer sampleBuffer: CMSampleBuffer, of type: SCStreamOutputType) {
        guard type == .screen,
              CMSampleBufferIsValid(sampleBuffer),
              CMSampleBufferDataIsReady(sampleBuffer) else { return }

        // Only forward "complete" frames; skip idle/blank/suspended buffers
        // (e.g. a duplicate frame when nothing on screen has changed).
        if let attachments = CMSampleBufferGetSampleAttachmentsArray(sampleBuffer, createIfNecessary: false) as? [[SCStreamFrameInfo: Any]],
           let info = attachments.first,
           let statusRaw = info[.status] as? Int,
           let status = SCFrameStatus(rawValue: statusRaw),
           status != .complete {
            return
        }

        frameHandler?(sampleBuffer)
    }

    // MARK: - SCStreamDelegate

    public func stream(_ stream: SCStream, didStopWithError error: Error) {
        NSLog("MacZoomer: SCStream stopped with error: \(error)")
    }
}
