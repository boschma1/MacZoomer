import AppKit
import Foundation
import ScreenCaptureKit

/// Top-level coordinator for screen recording. Handles three entry points
/// (full screen, region, focused window), permission gating, the floating
/// HUD, and writing the final MP4 to ``Preferences.recordingFolder``. Only
/// one recording can be in progress at a time.
@MainActor
final class RecordingMode {
    private let preferences: Preferences
    private let permissions: PermissionCoordinator

    private var session: RecordingSession?
    private var hud: RecordingHUD?
    private var windowPicker: WindowPicker?
    private var conversionHUD: ConversionHUD?

    private var isShowingPermissionAlert = false
    private var hasTriggeredSystemPermissionPrompt = false

    /// URL of the most recent successfully written MP4 in this app session.
    /// Used by ``convertLastRecordingToGIF()`` to find the source file.
    private(set) var lastRecordingURL: URL?

    /// True while a GIF conversion is in flight; prevents double-clicks
    /// from spawning two ffmpeg processes for the same file.
    private(set) var isConverting = false

    init(preferences: Preferences, permissions: PermissionCoordinator) {
        self.preferences = preferences
        self.permissions = permissions
    }

    var isRecording: Bool { session?.isRunning == true }

    // MARK: - Public entry points

    func toggleFullScreen() {
        if isRecording { stop(); return }
        Task { @MainActor in await startFullScreen() }
    }

    func toggleRegion() {
        if isRecording { stop(); return }
        Task { @MainActor in await startRegion() }
    }

    func toggleWindow() {
        if isRecording { stop(); return }
        Task { @MainActor in await startWindow() }
    }

    func stop() {
        guard let session else { return }
        let hud = self.hud
        session.stop { [weak self] result in
            Task { @MainActor in
                self?.session = nil
                hud?.hide()
                self?.hud = nil
                switch result {
                case .success(let url):
                    self?.lastRecordingURL = url
                    NSWorkspace.shared.activateFileViewerSelecting([url])
                case .failure(let error):
                    self?.presentError("Recording failed", text: error.localizedDescription)
                }
            }
        }
    }

    // MARK: - Sources

    private func startFullScreen() async {
        guard let (content, ownApp) = await loadShareableContent() else { return }
        guard let display = pickDisplayUnderCursor(in: content) else {
            presentError("No display found", text: "MacZoomer couldn't identify a display to record.")
            return
        }
        let url = makeOutputURL(suffix: "Full")
        startSession(source: .fullDisplay(display), outputURL: url, ownApp: ownApp)
    }

    private func startRegion() async {
        guard let (_, _) = await loadShareableContent() else { return }
        let selector = RegionSelector()
        selector.present { [weak self] selection in
            guard let self else { return }
            guard let selection else { return }
            Task { @MainActor in
                await self.startRegionRecording(with: selection)
            }
        }
    }

    private func startRegionRecording(with selection: RegionSelection) async {
        guard let (content, ownApp) = await loadShareableContent() else { return }
        guard let display = content.displays.first(where: { $0.displayID == selection.screenDisplayID }) else {
            presentError("Region recording", text: "The selected display is no longer available.")
            return
        }

        // Flip from NSScreen's bottom-left frame to SCStreamConfiguration's
        // top-left-origin coordinate space (in points, not pixels).
        let pointHeight = selection.screenFrame.height
        let flipped = CGRect(
            x: selection.screenLocalRect.origin.x,
            y: pointHeight - selection.screenLocalRect.origin.y - selection.screenLocalRect.height,
            width: selection.screenLocalRect.width,
            height: selection.screenLocalRect.height
        )
        let pixelSize = CGSize(
            width: max(2, Int(selection.screenLocalRect.width * selection.backingScale)),
            height: max(2, Int(selection.screenLocalRect.height * selection.backingScale))
        )

        let url = makeOutputURL(suffix: "Region")
        startSession(
            source: .region(display: display, sourceRect: flipped, pixelSize: pixelSize),
            outputURL: url,
            ownApp: ownApp
        )
    }

    private func startWindow() async {
        guard let (_, ownApp) = await loadShareableContent() else { return }
        let picker = WindowPicker()
        self.windowPicker = picker
        picker.present { [weak self] window in
            guard let self else { return }
            self.windowPicker = nil
            guard let window else { return }
            let url = self.makeOutputURL(suffix: "Window")
            self.startSession(source: .window(window), outputURL: url, ownApp: ownApp)
        }
    }

    // MARK: - Session lifecycle

    private func startSession(source: RecordingSource, outputURL: URL, ownApp: SCRunningApplication?) {
        do {
            let session = try RecordingSession(
                source: source,
                outputURL: outputURL,
                frameRate: preferences.recordingFrameRate,
                showsCursor: preferences.recordingShowsCursor,
                excludingOwnApp: ownApp
            )
            session.onFatalError = { [weak self] error in
                Task { @MainActor in
                    self?.handleFatalError(error)
                }
            }
            self.session = session
            let hud = RecordingHUD()
            hud.onStopTapped = { [weak self] in self?.stop() }
            self.hud = hud
            hud.show()

            Task { @MainActor in
                do {
                    try await session.start()
                } catch {
                    self.handleFatalError(error)
                }
            }
        } catch {
            handleFatalError(error)
        }
    }

    private func handleFatalError(_ error: Error) {
        session?.cancel()
        session = nil
        hud?.hide()
        hud = nil
        if let nsError = error as NSError?,
           nsError.domain == "com.apple.ScreenCaptureKit.SCStreamErrorDomain"
            || nsError.localizedDescription.lowercased().contains("not authorized")
            || nsError.localizedDescription.lowercased().contains("denied") {
            handlePermissionDenied()
        } else {
            presentError("Recording failed", text: error.localizedDescription)
        }
    }

    // MARK: - Helpers

    private func loadShareableContent() async -> (SCShareableContent, SCRunningApplication?)? {
        // Cheap preflight first: avoids spuriously triggering the permission
        // flow when SCShareableContent fails for some other transient reason,
        // and matches the pattern ScreenshotMode / LiveZoomMode use.
        guard CGPreflightScreenCaptureAccess() else {
            handlePermissionDenied()
            return nil
        }
        do {
            let content = try await SCShareableContent.excludingDesktopWindows(
                true,
                onScreenWindowsOnly: true
            )
            let pid = ProcessInfo.processInfo.processIdentifier
            let ownApp = content.applications.first { $0.processID == pid }
            return (content, ownApp)
        } catch {
            // If preflight said we're authorized but the call still fails,
            // that's a real error, not a permission issue.
            presentError("Recording failed", text: error.localizedDescription)
            return nil
        }
    }

    private func pickDisplayUnderCursor(in content: SCShareableContent) -> SCDisplay? {
        let cursor = NSEvent.mouseLocation
        for screen in NSScreen.screens {
            if NSPointInRect(cursor, screen.frame),
               let id = screen.deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? CGDirectDisplayID,
               let match = content.displays.first(where: { $0.displayID == id })
            {
                return match
            }
        }
        return content.displays.first
    }

    private func makeOutputURL(suffix: String) -> URL {
        let folder = preferences.recordingFolder
        try? FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd 'at' HH.mm.ss"
        let base = "MacZoomer Recording (\(suffix)) \(formatter.string(from: Date()))"
        return ImageFileWriter.uniqueFileURL(in: folder, baseName: base, ext: "mp4")
    }

    private func handlePermissionDenied() {
        if !hasTriggeredSystemPermissionPrompt {
            hasTriggeredSystemPermissionPrompt = true
            permissions.requestIfNeeded(.screenRecording)
            return
        }
        presentPermissionAlert()
    }

    private func presentPermissionAlert() {
        guard !isShowingPermissionAlert else { return }
        isShowingPermissionAlert = true
        defer { isShowingPermissionAlert = false }

        let alert = NSAlert()
        alert.messageText = "Screen Recording permission needed"
        alert.informativeText = """
            MacZoomer can't record the screen until Screen Recording is enabled in System Settings → Privacy & Security → Screen Recording.

            If you've already enabled it, MacZoomer must be quit and relaunched before macOS pushes the new grant into the running process. Click "Quit & Reopen" below to do that automatically.
            """
        alert.addButton(withTitle: "Quit & Reopen")
        alert.addButton(withTitle: "Open System Settings")
        alert.addButton(withTitle: "Cancel")
        switch alert.runModal() {
        case .alertFirstButtonReturn:
            Self.quitAndReopen()
        case .alertSecondButtonReturn:
            permissions.openSettings(for: .screenRecording)
        default:
            break
        }
    }

    /// Spawns a detached child process that waits briefly, then re-opens our
    /// app bundle. Then terminates the current process. macOS will load the
    /// fresh TCC grant on the new launch.
    private static func quitAndReopen() {
        let bundleURL = Bundle.main.bundleURL
        let task = Process()
        task.launchPath = "/bin/sh"
        task.arguments = [
            "-c",
            "sleep 0.5 && /usr/bin/open \"\(bundleURL.path)\"",
        ]
        do {
            try task.run()
        } catch {
            NSLog("MacZoomer: failed to schedule relaunch: \(error)")
        }
        NSApp.terminate(nil)
    }

    private func presentError(_ title: String, text: String) {
        let alert = NSAlert()
        alert.messageText = title
        alert.informativeText = text
        alert.alertStyle = .warning
        alert.addButton(withTitle: "OK")
        alert.runModal()
    }

    // MARK: - GIF conversion

    /// Convert ``lastRecordingURL`` to a sibling `.gif`. Runs asynchronously
    /// on a background queue and surfaces success/failure via `NSAlert`.
    /// Shows a helpful message when no recording exists yet or ffmpeg
    /// isn't installed. Safe to wire to a menu item.
    func convertLastRecordingToGIF() {
        guard !isConverting else {
            presentInfo(
                "Conversion already in progress",
                text: "MacZoomer is still converting the previous recording. Try again in a moment."
            )
            return
        }
        guard let source = lastRecordingURL else {
            presentInfo(
                "No recording to convert",
                text: "Record something first (⌘5 / ⌘⇧5 / ⌘⌥5), then choose this menu item to convert the latest recording to GIF."
            )
            return
        }
        guard FileManager.default.fileExists(atPath: source.path) else {
            lastRecordingURL = nil
            presentInfo(
                "Recording file missing",
                text: "The most recent recording at \(source.path) is no longer on disk. Record again, then retry."
            )
            return
        }

        let destination = source.deletingPathExtension().appendingPathExtension("gif")
        isConverting = true

        let hud = ConversionHUD()
        hud.show(filename: source.lastPathComponent)
        self.conversionHUD = hud

        Task { @MainActor in
            let result: Result<URL, Swift.Error>
            do {
                try await GIFExporter.convert(source: source, destination: destination)
                result = .success(destination)
            } catch {
                result = .failure(error)
            }

            // Tear down the HUD *before* any modal alert so the spinner
            // doesn't stay visible behind it.
            self.conversionHUD?.hide()
            self.conversionHUD = nil
            self.isConverting = false

            switch result {
            case .success(let gifURL):
                let alert = NSAlert()
                alert.messageText = "GIF saved"
                alert.informativeText = "Converted \(source.lastPathComponent) → \(gifURL.lastPathComponent)"
                alert.alertStyle = .informational
                alert.addButton(withTitle: "Reveal in Finder")
                alert.addButton(withTitle: "OK")
                if alert.runModal() == .alertFirstButtonReturn {
                    NSWorkspace.shared.activateFileViewerSelecting([gifURL])
                }
            case .failure(let error as GIFExporter.Error):
                presentError("GIF conversion failed", text: error.errorDescription ?? "Unknown error")
            case .failure(let error):
                presentError("GIF conversion failed", text: error.localizedDescription)
            }
        }
    }

    private func presentInfo(_ title: String, text: String) {
        let alert = NSAlert()
        alert.messageText = title
        alert.informativeText = text
        alert.alertStyle = .informational
        alert.addButton(withTitle: "OK")
        alert.runModal()
    }
}
