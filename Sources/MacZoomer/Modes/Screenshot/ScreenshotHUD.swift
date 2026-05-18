import AppKit

/// Brief floating notification shown after a screenshot action. Auto-fades.
/// One instance is reused across captures.
@MainActor
final class ScreenshotHUD {
    enum Event {
        case copied
        case saved(URL)
        case failed(String)
    }

    static let shared = ScreenshotHUD()

    private var window: NSWindow?
    private var hideTimer: Timer?

    private init() {}

    func show(_ event: Event) {
        let (text, image) = configuration(for: event)
        present(text: text, glyph: image)
    }

    private func configuration(for event: Event) -> (String, NSImage?) {
        switch event {
        case .copied:
            return ("Screenshot copied", NSImage(systemSymbolName: "doc.on.clipboard", accessibilityDescription: nil))
        case .saved(let url):
            return ("Saved: \(url.lastPathComponent)", NSImage(systemSymbolName: "checkmark.circle", accessibilityDescription: nil))
        case .failed(let message):
            return (message, NSImage(systemSymbolName: "exclamationmark.triangle", accessibilityDescription: nil))
        }
    }

    private func present(text: String, glyph: NSImage?) {
        hideTimer?.invalidate()
        window?.orderOut(nil)

        guard let screen = NSScreen.main ?? NSScreen.screens.first else { return }

        let container = NSStackView()
        container.orientation = .horizontal
        container.alignment = .centerY
        container.spacing = 10
        container.edgeInsets = NSEdgeInsets(top: 10, left: 14, bottom: 10, right: 16)
        container.wantsLayer = true
        container.layer?.cornerRadius = 12
        container.layer?.backgroundColor = NSColor.black.withAlphaComponent(0.75).cgColor

        if let glyph {
            let imageView = NSImageView(image: glyph)
            imageView.contentTintColor = .white
            imageView.symbolConfiguration = NSImage.SymbolConfiguration(pointSize: 16, weight: .semibold)
            container.addArrangedSubview(imageView)
        }

        let label = NSTextField(labelWithString: text)
        label.textColor = .white
        label.font = .systemFont(ofSize: 13, weight: .medium)
        container.addArrangedSubview(label)

        container.layoutSubtreeIfNeeded()
        let size = container.fittingSize

        let frame = NSRect(
            x: screen.frame.midX - size.width / 2,
            y: screen.frame.minY + screen.frame.height * 0.12,
            width: size.width,
            height: size.height
        )

        let w = NSWindow(
            contentRect: frame,
            styleMask: .borderless,
            backing: .buffered,
            defer: false
        )
        w.isOpaque = false
        w.backgroundColor = .clear
        w.hasShadow = false
        w.level = .statusBar
        w.ignoresMouseEvents = true
        w.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary]
        w.contentView = container
        w.alphaValue = 0
        w.orderFrontRegardless()

        NSAnimationContext.runAnimationGroup { ctx in
            ctx.duration = 0.12
            w.animator().alphaValue = 1
        }

        window = w
        hideTimer = Timer.scheduledTimer(withTimeInterval: 1.6, repeats: false) { [weak self] _ in
            MainActor.assumeIsolated {
                self?.dismiss()
            }
        }
    }

    private func dismiss() {
        guard let w = window else { return }
        NSAnimationContext.runAnimationGroup({ ctx in
            ctx.duration = 0.22
            w.animator().alphaValue = 0
        }, completionHandler: { [weak self] in
            MainActor.assumeIsolated {
                w.orderOut(nil)
                if self?.window === w { self?.window = nil }
            }
        })
    }
}
