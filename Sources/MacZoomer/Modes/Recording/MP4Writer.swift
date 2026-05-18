import AVFoundation
import CoreMedia
import CoreVideo
import Foundation

/// Wraps `AVAssetWriter` to receive `CMSampleBuffer`s from `SCStream` and
/// produce an H.264-encoded MP4 on disk. Single-shot: create, start, append
/// frames, finish. After ``finish(completion:)`` the writer cannot be reused.
@MainActor
final class MP4Writer {
    enum WriterError: Error, LocalizedError {
        case writerCreation(Error)
        case writerNotReady
        case missingImageBuffer
        case appendFailed
        case sessionNotStarted

        var errorDescription: String? {
            switch self {
            case .writerCreation(let e): return "Could not create video writer: \(e.localizedDescription)"
            case .writerNotReady:        return "Video writer wasn't ready before the first frame arrived."
            case .missingImageBuffer:    return "Captured sample had no pixel buffer."
            case .appendFailed:          return "Failed to append a video frame."
            case .sessionNotStarted:     return "Tried to append a frame before the writer was started."
            }
        }
    }

    let outputURL: URL
    let pixelWidth: Int
    let pixelHeight: Int

    private let writer: AVAssetWriter
    private let videoInput: AVAssetWriterInput
    private let pixelBufferAdaptor: AVAssetWriterInputPixelBufferAdaptor

    private var sessionStartTime: CMTime?
    private(set) var frameCount: Int = 0
    private(set) var isFinished: Bool = false

    init(outputURL: URL, pixelWidth: Int, pixelHeight: Int, averageBitRate: Int = 10_000_000) throws {
        self.outputURL = outputURL
        self.pixelWidth = pixelWidth
        self.pixelHeight = pixelHeight

        try? FileManager.default.removeItem(at: outputURL)
        do {
            self.writer = try AVAssetWriter(outputURL: outputURL, fileType: .mp4)
        } catch {
            throw WriterError.writerCreation(error)
        }

        let videoSettings: [String: Any] = [
            AVVideoCodecKey: AVVideoCodecType.h264,
            AVVideoWidthKey: pixelWidth,
            AVVideoHeightKey: pixelHeight,
            AVVideoCompressionPropertiesKey: [
                AVVideoAverageBitRateKey: averageBitRate,
                AVVideoProfileLevelKey: AVVideoProfileLevelH264HighAutoLevel,
                AVVideoMaxKeyFrameIntervalKey: 60
            ]
        ]

        self.videoInput = AVAssetWriterInput(mediaType: .video, outputSettings: videoSettings)
        videoInput.expectsMediaDataInRealTime = true

        let sourcePixelBufferAttributes: [String: Any] = [
            kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_32BGRA,
            kCVPixelBufferWidthKey as String: pixelWidth,
            kCVPixelBufferHeightKey as String: pixelHeight
        ]

        self.pixelBufferAdaptor = AVAssetWriterInputPixelBufferAdaptor(
            assetWriterInput: videoInput,
            sourcePixelBufferAttributes: sourcePixelBufferAttributes
        )

        guard writer.canAdd(videoInput) else {
            throw WriterError.writerNotReady
        }
        writer.add(videoInput)
    }

    func start() throws {
        guard writer.startWriting() else {
            throw writer.error.map { WriterError.writerCreation($0) } ?? WriterError.writerNotReady
        }
    }

    /// Append one frame. The first appended frame's pts becomes the session's
    /// time origin; subsequent frames are offset against it so the output
    /// starts at t=0 regardless of the absolute SCStream timestamps.
    func append(sampleBuffer: CMSampleBuffer) throws {
        guard !isFinished else { return }
        guard let imageBuffer = CMSampleBufferGetImageBuffer(sampleBuffer) else {
            throw WriterError.missingImageBuffer
        }

        let pts = CMSampleBufferGetPresentationTimeStamp(sampleBuffer)

        if sessionStartTime == nil {
            writer.startSession(atSourceTime: .zero)
            sessionStartTime = pts
        }
        guard let origin = sessionStartTime else { throw WriterError.sessionNotStarted }
        let relativePTS = CMTimeSubtract(pts, origin)

        guard videoInput.isReadyForMoreMediaData else {
            // Drop the frame rather than block — AVAssetWriter signals
            // back-pressure this way. SCStream will keep delivering at the
            // configured cadence and we'll catch up on the next one.
            return
        }

        if !pixelBufferAdaptor.append(imageBuffer, withPresentationTime: relativePTS) {
            throw WriterError.appendFailed
        }
        frameCount += 1
    }

    func finish(completion: @escaping @Sendable (Result<URL, Error>) -> Void) {
        guard !isFinished else { return }
        isFinished = true

        let outputURL = self.outputURL
        let writer = self.writer

        videoInput.markAsFinished()
        writer.finishWriting {
            if writer.status == .completed {
                completion(.success(outputURL))
            } else if let error = writer.error {
                completion(.failure(error))
            } else {
                completion(.failure(WriterError.writerNotReady))
            }
        }
    }

    func cancel() {
        guard !isFinished else { return }
        isFinished = true
        writer.cancelWriting()
        try? FileManager.default.removeItem(at: outputURL)
    }
}
