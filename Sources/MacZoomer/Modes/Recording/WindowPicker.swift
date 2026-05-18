import AppKit
import ScreenCaptureKit
import SwiftUI

/// Modal window-picker shown when the user invokes "Record Window" (⌘⌥5).
/// Lists every on-screen, user-visible window (filtering the desktop, dock,
/// notification center, and our own status item) and resolves to the chosen
/// `SCWindow` via a completion. Esc cancels.
@MainActor
final class WindowPicker {
    private var window: NSWindow?
    private var completion: ((SCWindow?) -> Void)?

    func present(completion: @escaping (SCWindow?) -> Void) {
        if self.window != nil { return }
        self.completion = completion

        Task { @MainActor in
            do {
                let content = try await SCShareableContent.excludingDesktopWindows(
                    true,
                    onScreenWindowsOnly: true
                )
                let candidates = content.windows.filter { window in
                    guard let title = window.title, !title.isEmpty else { return false }
                    if window.owningApplication?.bundleIdentifier == Bundle.main.bundleIdentifier {
                        return false
                    }
                    if window.frame.width < 50 || window.frame.height < 50 { return false }
                    return true
                }
                showPicker(windows: candidates)
            } catch {
                NSLog("MacZoomer: WindowPicker content fetch failed: \(error)")
                finish(with: nil)
            }
        }
    }

    private func showPicker(windows: [SCWindow]) {
        if windows.isEmpty {
            let alert = NSAlert()
            alert.messageText = "No windows to record"
            alert.informativeText = "Open a window with a title and try again."
            alert.addButton(withTitle: "OK")
            alert.runModal()
            finish(with: nil)
            return
        }

        let panel = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 460, height: 360),
            styleMask: [.titled, .closable],
            backing: .buffered,
            defer: false
        )
        panel.title = "Choose a window to record"
        panel.isReleasedWhenClosed = false
        panel.level = .modalPanel
        panel.identifier = NSUserInterfaceItemIdentifier("MacZoomerWindowPicker")

        let view = WindowPickerView(
            windows: windows.map(SCWindowChoice.init),
            onSelect: { [weak self] choice in self?.finish(with: choice.window) },
            onCancel: { [weak self] in self?.finish(with: nil) }
        )
        let host = NSHostingController(rootView: view)
        host.preferredContentSize = NSSize(width: 460, height: 360)
        panel.contentViewController = host
        panel.center()
        panel.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)

        self.window = panel
    }

    private func finish(with window: SCWindow?) {
        self.window?.orderOut(nil)
        self.window = nil
        let cb = completion
        completion = nil
        cb?(window)
    }
}

struct SCWindowChoice: Identifiable, Hashable {
    let id: CGWindowID
    let title: String
    let appName: String
    let bundleIdentifier: String?
    let window: SCWindow

    init(_ window: SCWindow) {
        self.id = window.windowID
        self.title = window.title ?? "Untitled"
        self.appName = window.owningApplication?.applicationName ?? "Unknown"
        self.bundleIdentifier = window.owningApplication?.bundleIdentifier
        self.window = window
    }

    static func == (lhs: SCWindowChoice, rhs: SCWindowChoice) -> Bool { lhs.id == rhs.id }
    func hash(into hasher: inout Hasher) { hasher.combine(id) }
}

struct WindowPickerView: View {
    let windows: [SCWindowChoice]
    let onSelect: (SCWindowChoice) -> Void
    let onCancel: () -> Void

    @State private var selection: SCWindowChoice.ID?

    var body: some View {
        VStack(spacing: 0) {
            List(selection: $selection) {
                ForEach(windows) { choice in
                    HStack(spacing: 8) {
                        Image(systemName: "macwindow")
                            .foregroundStyle(.secondary)
                            .accessibilityHidden(true)
                        VStack(alignment: .leading, spacing: 1) {
                            Text(choice.title)
                                .font(.body)
                                .lineLimit(1)
                            Text(choice.appName)
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                        Spacer()
                    }
                    .tag(choice.id)
                    .contentShape(Rectangle())
                    .onTapGesture(count: 2) { onSelect(choice) }
                }
            }

            Divider()

            HStack {
                Spacer()
                Button("Cancel", role: .cancel) { onCancel() }
                    .keyboardShortcut(.cancelAction)
                Button("Record") {
                    if let id = selection,
                       let choice = windows.first(where: { $0.id == id }) {
                        onSelect(choice)
                    }
                }
                .keyboardShortcut(.defaultAction)
                .disabled(selection == nil)
            }
            .padding(12)
        }
    }
}
