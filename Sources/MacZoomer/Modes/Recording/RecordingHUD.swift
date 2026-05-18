import AppKit
import SwiftUI

/// Small always-on-top window shown while a recording is in progress. Has a
/// red pulsing dot, an elapsed time readout, and a Stop button. Auto-pinned
/// to the top-right of the main screen, below the menu bar. Excluded from
/// `SCStream` capture via `SCContentFilter`'s app-exclusion list so it
/// doesn't appear in the recording.
@MainActor
final class RecordingHUD {
    private var window: NSPanel?
    private var hostingView: NSHostingView<RecordingHUDView>?
    private var viewModel = RecordingHUDViewModel()

    var onStopTapped: (() -> Void)?

    func show() {
        if window != nil { return }
        viewModel.elapsed = 0
        viewModel.startedAt = Date()
        viewModel.onStop = { [weak self] in self?.onStopTapped?() }
        viewModel.startTimer()

        let panel = NSPanel(
            contentRect: NSRect(x: 0, y: 0, width: 200, height: 38),
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )
        panel.isFloatingPanel = true
        panel.level = .statusBar
        panel.collectionBehavior = [.canJoinAllSpaces, .stationary, .ignoresCycle, .fullScreenAuxiliary]
        panel.hasShadow = true
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hidesOnDeactivate = false
        panel.identifier = NSUserInterfaceItemIdentifier("MacZoomerRecordingHUD")
        panel.isMovableByWindowBackground = true

        let host = NSHostingView(rootView: RecordingHUDView(model: viewModel))
        host.frame = NSRect(x: 0, y: 0, width: 200, height: 38)
        panel.contentView = host

        positionTopRight(panel: panel)

        panel.orderFrontRegardless()
        self.window = panel
        self.hostingView = host
    }

    func hide() {
        viewModel.stopTimer()
        window?.orderOut(nil)
        window = nil
        hostingView = nil
    }

    private func positionTopRight(panel: NSPanel) {
        guard let screen = NSScreen.main else { return }
        let visible = screen.visibleFrame
        let size = panel.frame.size
        let origin = NSPoint(
            x: visible.maxX - size.width - 12,
            y: visible.maxY - size.height - 12
        )
        panel.setFrameOrigin(origin)
    }
}

/// Drives the HUD's timer label. Lives in its own class so the SwiftUI
/// `@ObservedObject` driving the view stays cheap.
@MainActor
final class RecordingHUDViewModel: ObservableObject {
    @Published var elapsed: TimeInterval = 0
    var startedAt: Date?
    var onStop: (() -> Void)?

    private var timer: Timer?

    func startTimer() {
        stopTimer()
        let t = Timer(timeInterval: 0.25, repeats: true) { [weak self] _ in
            Task { @MainActor in
                guard let self, let start = self.startedAt else { return }
                self.elapsed = Date().timeIntervalSince(start)
            }
        }
        RunLoop.main.add(t, forMode: .common)
        timer = t
    }

    func stopTimer() {
        timer?.invalidate()
        timer = nil
    }

    var formattedElapsed: String {
        let total = Int(elapsed)
        let h = total / 3600
        let m = (total % 3600) / 60
        let s = total % 60
        if h > 0 {
            return String(format: "%d:%02d:%02d", h, m, s)
        }
        return String(format: "%02d:%02d", m, s)
    }
}

struct RecordingHUDView: View {
    @ObservedObject var model: RecordingHUDViewModel
    @State private var dotOpacity: Double = 1.0

    var body: some View {
        HStack(spacing: 8) {
            Circle()
                .fill(Color.red)
                .frame(width: 10, height: 10)
                .opacity(dotOpacity)
                .onAppear {
                    withAnimation(.easeInOut(duration: 0.8).repeatForever(autoreverses: true)) {
                        dotOpacity = 0.3
                    }
                }
                .accessibilityHidden(true)
            Text(model.formattedElapsed)
                .monospacedDigit()
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(.white)
            Spacer(minLength: 4)
            Button(action: { model.onStop?() }) {
                Image(systemName: "stop.fill")
                    .foregroundStyle(.white)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 4)
                    .background(
                        RoundedRectangle(cornerRadius: 4)
                            .fill(Color.white.opacity(0.18))
                    )
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Stop recording")
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 6)
        .background(
            RoundedRectangle(cornerRadius: 8)
                .fill(Color.black.opacity(0.78))
        )
    }
}
