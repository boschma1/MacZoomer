import AppKit
import Combine
import CoreGraphics

public enum PermissionState: Equatable, Sendable {
    case unknown
    case granted
    case denied
    case notDetermined
}

public enum PermissionKind: String, CaseIterable, Sendable {
    case screenRecording
    case accessibility
    case inputMonitoring

    public var displayName: String {
        switch self {
        case .screenRecording: return "Screen Recording"
        case .accessibility:   return "Accessibility"
        case .inputMonitoring: return "Input Monitoring"
        }
    }

    public var rationale: String {
        switch self {
        case .screenRecording:
            return "Required to magnify, annotate, and record your screen."
        case .accessibility:
            return "Required so global hotkeys work in every app and Space."
        case .inputMonitoring:
            return "Required to capture mouse and keyboard while an overlay is on screen."
        }
    }

    public var systemSettingsURL: URL? {
        let host: String
        switch self {
        case .screenRecording: host = "Privacy_ScreenCapture"
        case .accessibility:   host = "Privacy_Accessibility"
        case .inputMonitoring: host = "Privacy_ListenEvent"
        }
        return URL(string: "x-apple.systempreferences:com.apple.preference.security?\(host)")
    }
}

/// Tracks the three TCC permissions MacZoomer needs and exposes deep links
/// into the corresponding System Settings panes.
@MainActor
public final class PermissionCoordinator: ObservableObject {
    @Published public private(set) var states: [PermissionKind: PermissionState] = [:]

    public init() {
        for kind in PermissionKind.allCases {
            states[kind] = .unknown
        }
    }

    public var allGranted: Bool {
        PermissionKind.allCases.allSatisfy { states[$0] == .granted }
    }

    public func refreshAll() {
        for kind in PermissionKind.allCases {
            states[kind] = checkStatus(for: kind)
        }
    }

    public func requestIfNeeded(_ kind: PermissionKind) {
        switch kind {
        case .screenRecording:
            // The cheapest way to trigger the TCC prompt is to attempt a
            // capture; CGPreflightScreenCaptureAccess + Request… is the
            // documented path.
            _ = CGPreflightScreenCaptureAccess()
            _ = CGRequestScreenCaptureAccess()
        case .accessibility:
            let options: NSDictionary = [
                kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String: true
            ]
            _ = AXIsProcessTrustedWithOptions(options)
        case .inputMonitoring:
            // There is no public API to request Input Monitoring; the user
            // must add the app via System Settings. We open the pane.
            openSettings(for: kind)
        }
        refreshAll()
    }

    public func openSettings(for kind: PermissionKind) {
        guard let url = kind.systemSettingsURL else { return }
        NSWorkspace.shared.open(url)
    }

    // MARK: - Status detection

    private func checkStatus(for kind: PermissionKind) -> PermissionState {
        switch kind {
        case .screenRecording:
            return CGPreflightScreenCaptureAccess() ? .granted : .notDetermined
        case .accessibility:
            return AXIsProcessTrusted() ? .granted : .notDetermined
        case .inputMonitoring:
            // No first-party API. Treat as unknown until a feature using it
            // actually exercises CGEventTap and reports back.
            return .unknown
        }
    }
}
