import SwiftUI

// Settings is presented through ``SettingsTabViewController`` (AppKit's
// NSTabViewController in `.toolbar` style) for the classic icon-over-label
// preferences look. The individual pane views below are reused from there
// via NSHostingController.

struct GeneralSettingsView: View {
    @EnvironmentObject private var preferences: Preferences

    var body: some View {
        Form {
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

    var body: some View {
        VStack(alignment: .leading) {
            Text("Default bindings shown below. A hotkey-recorder UI ships in Phase 7.")
                .font(.callout)
                .foregroundStyle(.secondary)
                .padding(.bottom, 8)

            Table(HotkeyAction.allCases) {
                TableColumn("Action") { (action: HotkeyAction) in
                    Text(action.displayName)
                }
                TableColumn("Shortcut") { (action: HotkeyAction) in
                    Text(preferences.binding(for: action)?.displayString ?? "—")
                        .monospaced()
                }
            }
        }
        .padding()
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
            Text("MacZoomer").font(.title).bold()
            Text("Version \(Bundle.main.shortVersionString)")
                .foregroundStyle(.secondary)
            Text("Screen-zoom, annotation, and recording for macOS.")
                .multilineTextAlignment(.center)
                .padding(.top, 4)
            Link("github.com/markusbosch/MacZoomer",
                 destination: URL(string: "https://github.com/markusbosch/MacZoomer")!)
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
