import SwiftUI

// Settings is presented through ``SettingsTabViewController`` (AppKit's
// NSTabViewController in `.toolbar` style) for the classic icon-over-label
// preferences look. The individual pane views below are reused from there
// via NSHostingController.

struct GeneralSettingsView: View {
    @EnvironmentObject private var preferences: Preferences

    @State private var lastImportError: String?
    @State private var launchAtLogin: Bool = LaunchAtLogin.isEnabled
    @State private var launchAtLoginError: String?

    var body: some View {
        Form {
            Section("Startup") {
                Toggle("Launch MacZoomer at login", isOn: Binding(
                    get: { launchAtLogin },
                    set: { setLaunchAtLogin($0) }
                ))
                if let launchAtLoginError {
                    Text(launchAtLoginError)
                        .font(.caption)
                        .foregroundStyle(.red)
                }
                Text("MacZoomer will start automatically and appear in the menu bar when you log in. You can also manage this in System Settings → General → Login Items.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Section("Zoom") {
                Toggle("Animate zoom transitions", isOn: bindingFor(\.zoomAnimate))
                Toggle("Smooth the zoomed image",  isOn: bindingFor(\.zoomSmoothing))
                HStack {
                    Text("Initial magnification")
                    Slider(value: bindingFor(\.zoomInitialMagnification), in: 1.25...4.0, step: 0.25)
                    Text(String(format: "%.2f×", preferences.zoomInitialMagnification))
                        .monospacedDigit()
                        .frame(width: 50, alignment: .trailing)
                }
            }

            Section("Settings") {
                HStack {
                    Button("Import…") { runImport() }
                    Button("Export…") { runExport() }
                    Spacer()
                }
                if let lastImportError {
                    Text(lastImportError)
                        .font(.caption)
                        .foregroundStyle(.red)
                }
                Text("Export bundles every preference and customized shortcut into a JSON file. Importing replaces the current values.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .formStyle(.grouped)
        .padding()
        .onAppear { launchAtLogin = LaunchAtLogin.isEnabled }
    }

    private func setLaunchAtLogin(_ enabled: Bool) {
        do {
            try LaunchAtLogin.set(enabled)
            launchAtLogin = LaunchAtLogin.isEnabled
            launchAtLoginError = nil
        } catch {
            launchAtLogin = LaunchAtLogin.isEnabled
            launchAtLoginError = "Could not update launch-at-login: \(error.localizedDescription). If this keeps happening, toggle it from System Settings → General → Login Items."
        }
    }

    private func bindingFor<V>(_ keyPath: ReferenceWritableKeyPath<Preferences, V>) -> Binding<V> {
        Binding(
            get: { preferences[keyPath: keyPath] },
            set: { preferences[keyPath: keyPath] = $0; preferences.objectWillChange.send() }
        )
    }

    private func runExport() {
        let panel = NSSavePanel()
        panel.title = "Export MacZoomer Settings"
        panel.nameFieldStringValue = "MacZoomer Settings.json"
        panel.allowedContentTypes = [.json]
        panel.canCreateDirectories = true
        guard panel.runModal() == .OK, let url = panel.url else { return }
        do {
            let data = try preferences.exportToData()
            try data.write(to: url, options: .atomic)
            lastImportError = nil
        } catch {
            lastImportError = "Export failed: \(error.localizedDescription)"
        }
    }

    private func runImport() {
        let panel = NSOpenPanel()
        panel.title = "Import MacZoomer Settings"
        panel.allowedContentTypes = [.json]
        panel.allowsMultipleSelection = false
        panel.canChooseDirectories = false
        guard panel.runModal() == .OK, let url = panel.url else { return }
        do {
            let data = try Data(contentsOf: url)
            try preferences.importFromData(data)
            lastImportError = nil
        } catch {
            lastImportError = "Import failed: \(error.localizedDescription)"
        }
    }
}

struct ScreenshotsSettingsView: View {
    @EnvironmentObject private var preferences: Preferences

    var body: some View {
        Form {
            Section("Save location") {
                HStack {
                    Text(preferences.screenshotFolder.path)
                        .font(.callout.monospaced())
                        .lineLimit(1)
                        .truncationMode(.middle)
                        .frame(maxWidth: .infinity, alignment: .leading)
                    Button("Choose…") { chooseFolder() }
                    Button("Reveal") {
                        NSWorkspace.shared.activateFileViewerSelecting([preferences.screenshotFolder])
                    }
                }
                Text("Used by ⌘⌃6 (full screen) and ⌘⇧⌃6 (region). PNG files land in this folder with auto-incremented names if a file already exists.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Section("Shortcuts") {
                Text("Copy Screenshot: \(preferences.binding(for: .snapshotClipboard)?.displayString ?? "—")")
                Text("Copy Region: \(preferences.binding(for: .snapshotRegionClipboard)?.displayString ?? "—")")
                Text("Save Screenshot: \(preferences.binding(for: .snapshotFile)?.displayString ?? "—")")
                Text("Save Region: \(preferences.binding(for: .snapshotRegionFile)?.displayString ?? "—")")
            }
            .font(.callout)
        }
        .formStyle(.grouped)
        .padding()
    }

    private func chooseFolder() {
        let panel = NSOpenPanel()
        panel.title = "Choose screenshot folder"
        panel.canChooseFiles = false
        panel.canChooseDirectories = true
        panel.allowsMultipleSelection = false
        panel.canCreateDirectories = true
        panel.directoryURL = preferences.screenshotFolder
        if panel.runModal() == .OK, let url = panel.url {
            preferences.screenshotFolder = url
        }
    }
}

struct RecordingSettingsView: View {
    @EnvironmentObject private var preferences: Preferences

    var body: some View {
        Form {
            Section("Save location") {
                HStack {
                    Text(preferences.recordingFolder.path)
                        .font(.callout.monospaced())
                        .lineLimit(1)
                        .truncationMode(.middle)
                        .frame(maxWidth: .infinity, alignment: .leading)
                    Button("Choose…") { chooseFolder() }
                    Button("Reveal") {
                        NSWorkspace.shared.activateFileViewerSelecting([preferences.recordingFolder])
                    }
                }
                Text("MP4 recordings save here with auto-incremented names. Default is ~/Movies.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Section("Capture") {
                Picker("Format", selection: Binding(
                    get: { preferences.recordFormat },
                    set: { preferences.recordFormat = $0 }
                )) {
                    Text("MP4 (H.264)").tag(RecordingFormat.mp4)
                    Text("GIF — coming in v1.1").tag(RecordingFormat.gif)
                }
                .pickerStyle(.menu)

                Picker("Frame rate", selection: Binding(
                    get: { preferences.recordingFrameRate },
                    set: { preferences.recordingFrameRate = $0 }
                )) {
                    Text("24 fps").tag(24)
                    Text("30 fps").tag(30)
                    Text("60 fps").tag(60)
                }
                .pickerStyle(.segmented)

                Toggle("Include mouse cursor", isOn: Binding(
                    get: { preferences.recordingShowsCursor },
                    set: { preferences.recordingShowsCursor = $0 }
                ))

                Text("Audio recording will arrive in v1.1.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Section("Shortcuts") {
                Text("Record Screen: \(preferences.binding(for: .record)?.displayString ?? "—")")
                Text("Record Region: \(preferences.binding(for: .recordRegion)?.displayString ?? "—")")
                Text("Record Window: \(preferences.binding(for: .recordWindow)?.displayString ?? "—")")
            }
            .font(.callout)
        }
        .formStyle(.grouped)
        .padding()
    }

    private func chooseFolder() {
        let panel = NSOpenPanel()
        panel.title = "Choose recording folder"
        panel.canChooseFiles = false
        panel.canChooseDirectories = true
        panel.allowsMultipleSelection = false
        panel.canCreateDirectories = true
        panel.directoryURL = preferences.recordingFolder
        if panel.runModal() == .OK, let url = panel.url {
            preferences.recordingFolder = url
        }
    }
}

struct BreakTimerSettingsView: View {
    @EnvironmentObject private var preferences: Preferences

    private static let presets: [Int] = [1, 5, 10, 15, 20, 30, 45, 60]

    var body: some View {
        Form {
            Section("Duration") {
                HStack(spacing: 8) {
                    TextField(
                        "Minutes",
                        value: bindingFor(\.breakDurationMinutes),
                        formatter: Self.minuteFormatter
                    )
                    .textFieldStyle(.roundedBorder)
                    .frame(width: 70)
                    .multilineTextAlignment(.trailing)
                    .monospacedDigit()
                    Stepper(
                        "",
                        value: bindingFor(\.breakDurationMinutes),
                        in: 1...240
                    )
                    .labelsHidden()
                    Text("minutes")
                        .foregroundStyle(.secondary)
                    Spacer()
                }

                HStack(spacing: 6) {
                    Text("Presets:")
                        .foregroundStyle(.secondary)
                    ForEach(Self.presets, id: \.self) { value in
                        Button("\(value)m") {
                            preferences.breakDurationMinutes = value
                            preferences.objectWillChange.send()
                        }
                        .buttonStyle(.bordered)
                        .controlSize(.small)
                        .tint(preferences.breakDurationMinutes == value ? .accentColor : .secondary)
                    }
                }
            }

            Section("Appearance") {
                TextField("Message", text: bindingFor(\.breakMessage))
                    .textFieldStyle(.roundedBorder)
                HStack {
                    Text("Background opacity")
                    Slider(value: bindingFor(\.breakOpacity), in: 0.5...1.0, step: 0.05)
                    Text(String(format: "%.0f%%", preferences.breakOpacity * 100))
                        .monospacedDigit()
                        .frame(width: 50, alignment: .trailing)
                }
            }

            Section("Behavior") {
                Toggle("Lock workstation on start", isOn: bindingFor(\.breakLockOnStart))
                Text("Lock workstation isn't wired up yet — coming in a later release.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Section {
                Label {
                    Text("Shortcut: \(preferences.binding(for: .breakTimer)?.displayString ?? "—")  •  In overlay: Space pause, ↑/↓ ±1 min, ←/→ ±10 s, R reset, Esc exit.")
                        .font(.caption)
                } icon: {
                    Image(systemName: "info.circle")
                }
                .foregroundStyle(.secondary)
            }
        }
        .formStyle(.grouped)
        .padding()
    }

    private func bindingFor<V>(_ keyPath: ReferenceWritableKeyPath<Preferences, V>) -> Binding<V> {
        Binding(
            get: { preferences[keyPath: keyPath] },
            set: { preferences[keyPath: keyPath] = $0; preferences.objectWillChange.send() }
        )
    }

    private static let minuteFormatter: NumberFormatter = {
        let f = NumberFormatter()
        f.numberStyle = .none
        f.minimum = 1
        f.maximum = 240
        f.allowsFloats = false
        return f
    }()
}

struct HotkeysSettingsView: View {
    @EnvironmentObject private var preferences: Preferences

    @State private var showResetConfirmation = false

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text("Click a shortcut to record. Press the new combination, or Esc to cancel / Delete to clear.")
                    .font(.callout)
                    .foregroundStyle(.secondary)
                Spacer()
                Button("Reset All to Defaults") {
                    showResetConfirmation = true
                }
                .controlSize(.small)
            }
            .padding(.bottom, 4)

            ScrollView {
                VStack(spacing: 0) {
                    ForEach(HotkeyAction.allCases) { action in
                        HStack {
                            Text(action.displayName)
                                .frame(maxWidth: .infinity, alignment: .leading)
                            HotkeyRecorderView(action: action)
                        }
                        .padding(.vertical, 4)
                        Divider()
                    }
                }
            }
        }
        .padding()
        .confirmationDialog(
            "Reset all shortcuts to their defaults?",
            isPresented: $showResetConfirmation,
            titleVisibility: .visible
        ) {
            Button("Reset", role: .destructive) {
                preferences.resetHotkeysToDefaults()
            }
            Button("Cancel", role: .cancel) { }
        } message: {
            Text("This undoes every customized shortcut. Other settings are untouched.")
        }
    }
}

struct PermissionsSettingsView: View {
    @EnvironmentObject private var permissions: PermissionCoordinator

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            ForEach(PermissionKind.allCases, id: \.self) { kind in
                PermissionRow(kind: kind, state: permissions.states[kind] ?? .unknown)
                    .environmentObject(permissions)
            }
            Spacer()
            Button("Re-check permissions") {
                permissions.refreshAll()
            }
        }
        .padding()
    }
}

private struct PermissionRow: View {
    let kind: PermissionKind
    let state: PermissionState
    @EnvironmentObject private var permissions: PermissionCoordinator

    var body: some View {
        HStack(alignment: .top) {
            Image(systemName: iconName)
                .foregroundStyle(iconColor)
                .imageScale(.large)
                .frame(width: 24)
            VStack(alignment: .leading, spacing: 2) {
                Text(kind.displayName).font(.headline)
                Text(kind.rationale).font(.caption).foregroundStyle(.secondary)
            }
            Spacer()
            Button(state == .granted ? "Open Settings" : "Grant…") {
                if state == .granted {
                    permissions.openSettings(for: kind)
                } else {
                    permissions.requestIfNeeded(kind)
                }
            }
        }
    }

    private var iconName: String {
        switch state {
        case .granted: return "checkmark.circle.fill"
        case .denied:  return "xmark.circle.fill"
        default:       return "questionmark.circle"
        }
    }

    private var iconColor: Color {
        switch state {
        case .granted: return .green
        case .denied:  return .red
        default:       return .secondary
        }
    }
}

struct AboutSettingsView: View {
    var body: some View {
        VStack(spacing: 8) {
            Image(systemName: "plus.magnifyingglass")
                .font(.system(size: 48))
                .accessibilityHidden(true)
            Text("MacZoomer").font(.title).bold()
            Text("Version \(Bundle.main.shortVersionString)")
                .foregroundStyle(.secondary)
            Text("Screen-zoom, annotation, and recording for macOS.")
                .multilineTextAlignment(.center)
                .padding(.top, 4)
            Text("A Mac clone of Sysinternals' ZoomIt.")
                .font(.callout)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
            Link("github.com/boschma1/MacZoomer",
                 destination: URL(string: "https://github.com/boschma1/MacZoomer")!)
                .padding(.top, 8)
        }
        .padding()
    }
}

private extension Bundle {
    var shortVersionString: String {
        infoDictionary?["CFBundleShortVersionString"] as? String ?? "0.0.0"
    }
}
