import AppKit
import SwiftUI

/// Welcome / first-run window. Shows on the very first launch (and from
/// Settings → About → "Show Welcome" later), introduces the app, lists the
/// default shortcuts, and surfaces a live Screen Recording grant status
/// button. Sets ``Preferences.didCompleteOnboarding`` on dismissal so it
/// won't reappear automatically.
@MainActor
final class OnboardingWindowController: NSWindowController {
    private let preferences: Preferences
    private let permissions: PermissionCoordinator

    init(preferences: Preferences, permissions: PermissionCoordinator) {
        self.preferences = preferences
        self.permissions = permissions

        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 560, height: 540),
            styleMask: [.titled, .closable, .miniaturizable],
            backing: .buffered,
            defer: false
        )
        window.title = "Welcome to MacZoomer"
        window.identifier = NSUserInterfaceItemIdentifier("MacZoomerOnboarding")
        window.isReleasedWhenClosed = false
        window.center()

        super.init(window: window)

        let view = OnboardingView(
            preferences: preferences,
            permissions: permissions,
            dismiss: { [weak self] in self?.close() }
        )
        let host = NSHostingController(rootView: view)
        host.preferredContentSize = NSSize(width: 560, height: 540)
        window.contentViewController = host
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError() }

    func show() {
        guard let window else { return }
        if !window.isVisible { window.center() }
        window.makeKeyAndOrderFront(nil)
        window.orderFrontRegardless()
    }

    override func close() {
        preferences.didCompleteOnboarding = true
        super.close()
    }
}

private struct OnboardingView: View {
    let preferences: Preferences
    @ObservedObject var permissions: PermissionCoordinator
    let dismiss: () -> Void

    init(preferences: Preferences, permissions: PermissionCoordinator, dismiss: @escaping () -> Void) {
        self.preferences = preferences
        self.permissions = permissions
        self.dismiss = dismiss
    }

    private static let shortcuts: [(symbol: String, name: String, defaultKey: String)] = [
        ("plus.magnifyingglass", "Zoom",        "⌘1"),
        ("scribble",             "Draw",         "⌘2"),
        ("timer",                "Break Timer",  "⌘3"),
        ("dot.radiowaves.left.and.right", "Live Zoom", "⌘4"),
        ("camera.on.rectangle",  "Copy Screenshot", "⌘6"),
        ("photo.on.rectangle",   "Copy Region",  "⌘⇧6")
    ]

    var body: some View {
        VStack(spacing: 0) {
            header

            ScrollView {
                VStack(alignment: .leading, spacing: 18) {
                    introBlock
                    shortcutsBlock
                    permissionsBlock
                }
                .padding(.horizontal, 28)
                .padding(.vertical, 18)
            }

            Divider()
            footer
        }
        .frame(minWidth: 560, minHeight: 540)
        .onAppear { permissions.refreshAll() }
    }

    private var header: some View {
        VStack(spacing: 6) {
            Image(systemName: "plus.magnifyingglass")
                .font(.system(size: 44, weight: .regular))
                .foregroundStyle(.tint)
                .accessibilityHidden(true)
            Text("Welcome to MacZoomer")
                .font(.title).bold()
            Text("A Mac clone of Sysinternals' ZoomIt.")
                .font(.callout)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity)
        .padding(.top, 22)
        .padding(.bottom, 14)
    }

    private var introBlock: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text("What MacZoomer does")
                .font(.headline)
            Text("MacZoomer lives in your menu bar and turns global hotkeys into presenter-grade tools: freeze and zoom into the screen, draw on top of it, magnify in real time, snap screenshots, and run a full-screen break timer.")
                .foregroundStyle(.primary)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    private var shortcutsBlock: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("Default shortcuts")
                .font(.headline)
            VStack(spacing: 4) {
                ForEach(Self.shortcuts, id: \.name) { row in
                    HStack {
                        Image(systemName: row.symbol)
                            .frame(width: 22)
                            .foregroundStyle(.secondary)
                            .accessibilityHidden(true)
                        Text(row.name).frame(width: 160, alignment: .leading)
                        Text(row.defaultKey)
                            .monospaced()
                            .foregroundStyle(.secondary)
                        Spacer()
                    }
                    .padding(.vertical, 2)
                }
            }
            Text("Every shortcut is rebindable in Settings → Hotkeys.")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
    }

    private var permissionsBlock: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("One required permission")
                .font(.headline)
            HStack(spacing: 10) {
                Image(systemName: screenRecordingGranted ? "checkmark.circle.fill" : "exclamationmark.triangle.fill")
                    .foregroundStyle(screenRecordingGranted ? .green : .orange)
                    .imageScale(.large)
                    .accessibilityLabel(screenRecordingGranted ? "Granted" : "Not granted")
                VStack(alignment: .leading, spacing: 2) {
                    Text("Screen Recording")
                        .font(.subheadline).bold()
                    Text(screenRecordingGranted
                         ? "Granted — you're all set."
                         : "Needed for Zoom, Live Zoom, Screenshots, and Recording.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                Spacer()
                if !screenRecordingGranted {
                    Button("Grant…") {
                        permissions.requestIfNeeded(.screenRecording)
                    }
                }
            }
            .padding(10)
            .background(
                RoundedRectangle(cornerRadius: 8)
                    .fill(Color(nsColor: .controlBackgroundColor))
            )
            if !screenRecordingGranted {
                Text("After enabling Screen Recording in System Settings, you'll need to quit MacZoomer from the menu bar and relaunch it — macOS only applies the grant on a fresh launch.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    private var footer: some View {
        HStack {
            Spacer()
            Button("Get started") { dismiss() }
                .keyboardShortcut(.defaultAction)
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 12)
    }

    private var screenRecordingGranted: Bool {
        permissions.states[.screenRecording] == .granted
    }
}
