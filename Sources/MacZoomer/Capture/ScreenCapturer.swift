import AppKit
import CoreGraphics
import ScreenCaptureKit

/// One captured display, ready to be presented in a zoom overlay.
/// `NSScreen` is not Sendable, so this struct is intended to be consumed on
/// MainActor only — the actor that produces it transfers it via
/// `@MainActor`-isolated calls.
public struct DisplayCapture {
    public let screen: NSScreen
    public let displayID: CGDirectDisplayID
    public let image: CGImage
    /// Pixels per point of the captured image. 2 on Retina, 1 on standard displays.
    public let backingScale: CGFloat
}

public enum ScreenCaptureError: Error {
    case permissionDenied
    case noDisplays
    case captureFailed(Error)
}

/// One-shot screen captures via `SCScreenshotManager`.
/// Marked `@MainActor` because it interleaves Cocoa (`NSScreen`) and
/// ScreenCaptureKit calls; the few async hops it makes happen via `await`.
@MainActor
public final class ScreenCapturer {
    public init() {}

    /// Captures every connected display at native pixel resolution.
    public func captureAllDisplays() async throws -> [DisplayCapture] {
        guard CGPreflightScreenCaptureAccess() else {
            throw ScreenCaptureError.permissionDenied
        }

        let content: SCShareableContent
        do {
            content = try await SCShareableContent.excludingDesktopWindows(
                false,
                onScreenWindowsOnly: true
            )
        } catch {
            throw ScreenCaptureError.captureFailed(error)
        }

        guard !content.displays.isEmpty else {
            throw ScreenCaptureError.noDisplays
        }

        let nsScreensByID: [CGDirectDisplayID: NSScreen] = Dictionary(
            uniqueKeysWithValues: NSScreen.screens.compactMap { screen in
                screen.displayID.map { ($0, screen) }
            }
        )

        var results: [DisplayCapture] = []
        results.reserveCapacity(content.displays.count)

        for display in content.displays {
            guard let screen = nsScreensByID[display.displayID] else { continue }

            let filter = SCContentFilter(display: display, excludingWindows: [])
            let config = SCStreamConfiguration()
            config.width = Int(display.width)
            config.height = Int(display.height)
            config.showsCursor = false

            do {
                let image = try await SCScreenshotManager.captureImage(
                    contentFilter: filter,
                    configuration: config
                )
                results.append(DisplayCapture(
                    screen: screen,
                    displayID: display.displayID,
                    image: image,
                    backingScale: screen.backingScaleFactor
                ))
            } catch {
                throw ScreenCaptureError.captureFailed(error)
            }
        }

        return results
    }
}

public extension NSScreen {
    /// `CGDirectDisplayID` for this screen, pulled from its device description.
    var displayID: CGDirectDisplayID? {
        let key = NSDeviceDescriptionKey("NSScreenNumber")
        return deviceDescription[key] as? CGDirectDisplayID
    }
}
