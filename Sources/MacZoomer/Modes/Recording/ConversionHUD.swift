import AppKit
import SwiftUI

/// Borderless floating panel shown while ``GIFExporter`` is running. Sits
/// in the top-right corner of the main screen, displays an indeterminate
/// progress spinner with a label, and is dismissed by the caller when the
/// conversion task completes or fails.
@MainActor
final class ConversionHUD {
    private var window: NSPanel?
    private var hostingView: NSHostingView<ConversionHUDView>?

    func show(filename: String) {
        if window != nil { return }

        let model = ConversionHUDViewModel(filename: filename)

        let panel = NSPanel(
            contentRect: NSRect(x: 0, y: 0, width: 260, height: 44),
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
        panel.identifier = NSUserInterfaceItemIdentifier("MacZoomerConversionHUD")
        panel.isMovableByWindowBackground = true

        let host = NSHostingView(rootView: ConversionHUDView(model: model))
        host.frame = NSRect(x: 0, y: 0, width: 260, height: 44)
        panel.contentView = host

        positionTopRight(panel: panel)
        panel.orderFrontRegardless()

        self.window = panel
        self.hostingView = host
    }

    func hide() {
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

@MainActor
private final class ConversionHUDViewModel: ObservableObject {
    let filename: String

    init(filename: String) {
        self.filename = filename
    }
}

private struct ConversionHUDView: View {
    @ObservedObject var model: ConversionHUDViewModel

    var body: some View {
        HStack(spacing: 10) {
            ProgressIndicator()
                .frame(width: 16, height: 16)
            VStack(alignment: .leading, spacing: 1) {
                Text("Converting to GIF…")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(.white)
                Text(model.filename)
                    .font(.system(size: 10))
                    .foregroundStyle(.white.opacity(0.7))
                    .lineLimit(1)
                    .truncationMode(.middle)
            }
            Spacer(minLength: 4)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .background(
            RoundedRectangle(cornerRadius: 8)
                .fill(Color.black.opacity(0.78))
        )
        .accessibilityElement(children: .combine)
        .accessibilityLabel("Converting recording to GIF: \(model.filename)")
    }
}

/// Bridges the AppKit `NSProgressIndicator` into SwiftUI because SwiftUI's
/// own `ProgressView(value: ...)` and `ProgressView()` styles render with
/// a chrome that doesn't sit cleanly on a dark HUD background.
private struct ProgressIndicator: NSViewRepresentable {
    func makeNSView(context: Context) -> NSProgressIndicator {
        let indicator = NSProgressIndicator()
        indicator.style = .spinning
        indicator.isIndeterminate = true
        indicator.controlSize = .small
        indicator.appearance = NSAppearance(named: .darkAqua)
        indicator.startAnimation(nil)
        return indicator
    }

    func updateNSView(_ nsView: NSProgressIndicator, context: Context) {}
}
