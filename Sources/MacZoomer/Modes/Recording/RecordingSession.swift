import AppKit
import AVFoundation
import CoreMedia
import Foundation
import ScreenCaptureKit

/// What region of the screen to capture.
enum RecordingSource {
    case fullDisplay(SCDisplay)
    case region(display: SCDisplay, sourceRect: CGRect, pixelSize: CGSize)
    case window(SCWindow)
}

/// Owns an `SCStream` and an `MP4Writer`, bridging the two. Receives sample
/// buffers from ScreenCaptureKit on a private serial queue, hops back to the
/// main actor, and appends each frame to the writer. Cleanup happens on
/// ``stop(completion:)``, after which the session is single-use.
@MainActor
final class RecordingSession: NSObject, SCStreamDelegate, SCStreamOutput {
    enum SessionError: Error, LocalizedError {
        case shareableContentMissing
        case streamCreation(Error)
        case streamStart(Error)
        case writerFailure(Error)

        var errorDescription: String? {
            switch self {
            case .shareableContentMissing: return "Couldn't read shareable content from ScreenCaptureKit."
            case .streamCreation(let e):   return "Couldn't start screen recording stream: \(e.localizedDescription)"
            case .streamStart(let e):      return "Couldn't start screen recording stream: \(e.localizedDescription)"
            case .writerFailure(let e):    return "Recording writer failed: \(e.localizedDescription)"
            }
        }
    }

    let source: RecordingSource
    let outputURL: URL
    let frameRate: Int
    let showsCursor: Bool

    private var stream: SCStream!
    private let writer: MP4Writer
    private let sampleQueue: DispatchQueue
    private(set) var isRunning: Bool = false
    private(set) var startedAt: Date?

    var onFatalError: ((Error) -> Void)?

    init(source: RecordingSource,
         outputURL: URL,
         frameRate: Int,
         showsCursor: Bool,
         excludingOwnApp: SCRunningApplication?) throws
    {
        self.source = source
        self.outputURL = outputURL
        self.frameRate = frameRate
        self.showsCursor = showsCursor
        self.sampleQueue = DispatchQueue(
            label: "com.markusbosch.MacZoomer.recordingSample",
            qos: .userInteractive
        )

        let filter: SCContentFilter
        let pixelSize: CGSize
        let sourceRectInConfig: CGRect?

        switch source {
        case .fullDisplay(let display):
            let excluded = excludingOwnApp.map { [$0] } ?? []
            filter = SCContentFilter(
                display: display,
                excludingApplications: excluded,
                exceptingWindows: []
            )
            pixelSize = CGSize(width: display.width, height: display.height)
            sourceRectInConfig = nil

        case .region(let display, let sourceRect, let pixels):
            let excluded = excludingOwnApp.map { [$0] } ?? []
            filter = SCContentFilter(
                display: display,
                excludingApplications: excluded,
                exceptingWindows: []
            )
            pixelSize = pixels
            sourceRectInConfig = sourceRect

        case .window(let window):
            filter = SCContentFilter(desktopIndependentWindow: window)
            let frame = window.frame
            let scale = Self.scaleForWindow(window)
            pixelSize = CGSize(
                width: max(2, Int(frame.width * scale)),
                height: max(2, Int(frame.height * scale))
            )
            sourceRectInConfig = nil
        }

        let config = SCStreamConfiguration()
        config.width = Int(pixelSize.width)
        config.height = Int(pixelSize.height)
        config.pixelFormat = kCVPixelFormatType_32BGRA
        config.minimumFrameInterval = CMTime(value: 1, timescale: CMTimeScale(max(1, frameRate)))
        config.queueDepth = 6
        config.showsCursor = showsCursor
        if let rect = sourceRectInConfig {
            config.sourceRect = rect
        }

        self.writer = try MP4Writer(
            outputURL: outputURL,
            pixelWidth: Int(pixelSize.width),
            pixelHeight: Int(pixelSize.height)
        )

        super.init()

        self.stream = SCStream(filter: filter, configuration: config, delegate: self)
        do {
            try stream.addStreamOutput(self, type: .screen, sampleHandlerQueue: sampleQueue)
        } catch {
            throw SessionError.streamCreation(error)
        }
    }

    func start() async throws {
        try writer.start()
        do {
            try await stream.startCapture()
        } catch {
            writer.cancel()
            throw SessionError.streamStart(error)
        }
        isRunning = true
        startedAt = Date()
    }

    /// Stops the stream, flushes the writer, and reports the final file URL
    /// (or an error). After this returns the session is single-use.
    func stop(completion: @escaping @Sendable (Result<URL, Error>) -> Void) {
        guard isRunning else { return }
        isRunning = false

        let writer = self.writer
        Task {
            do {
                try await stream.stopCapture()
            } catch {
                // Continue with finish — partial output is still usable.
                NSLog("MacZoomer: SCStream stopCapture failed: \(error)")
            }
            await MainActor.run {
                writer.finish(completion: completion)
            }
        }
    }

    func cancel() {
        guard isRunning else { return }
        isRunning = false
        writer.cancel()
        Task { try? await stream.stopCapture() }
    }

    // MARK: - SCStreamOutput

    nonisolated func stream(_ stream: SCStream,
                            didOutputSampleBuffer sampleBuffer: CMSampleBuffer,
                            of type: SCStreamOutputType)
    {
        guard type == .screen, sampleBuffer.isValid else { return }

        if let attachments = CMSampleBufferGetSampleAttachmentsArray(sampleBuffer, createIfNecessary: false),
           let first = (attachments as? [[SCStreamFrameInfo: Any]])?.first,
           let statusRaw = first[.status] as? Int,
           let status = SCFrameStatus(rawValue: statusRaw),
           status != .complete
        {
            return
        }

        Task { @MainActor [weak self] in
            guard let self else { return }
            do {
                try self.writer.append(sampleBuffer: sampleBuffer)
            } catch {
                self.onFatalError?(error)
            }
        }
    }

    // MARK: - SCStreamDelegate

    nonisolated func stream(_ stream: SCStream, didStopWithError error: Error) {
        NSLog("MacZoomer: recording stream stopped with error: \(error)")
        Task { @MainActor [weak self] in
            self?.onFatalError?(error)
        }
    }

    /// SCWindow doesn't expose a backing-scale directly; figure out which
    /// NSScreen the window lives on and use that screen's scale factor.
    /// Falls back to the main screen's scale, then 2.0.
    private static func scaleForWindow(_ window: SCWindow) -> CGFloat {
        let frame = window.frame
        // SCWindow.frame is in top-left coordinates. Use the centerpoint and
        // convert into Cocoa's bottom-left space to test against NSScreen.
        let primaryScreenHeight = NSScreen.screens.first?.frame.height ?? frame.height
        let center = CGPoint(
            x: frame.midX,
            y: primaryScreenHeight - frame.midY
        )
        for screen in NSScreen.screens where NSPointInRect(center, screen.frame) {
            return screen.backingScaleFactor
        }
        return NSScreen.main?.backingScaleFactor ?? 2.0
    }
}
