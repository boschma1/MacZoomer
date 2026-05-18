import Combine
import Foundation
import AppKit

/// Single source of truth for user-configurable settings. Backed by
/// `UserDefaults` so values persist across launches. SwiftUI views observe
/// via `@EnvironmentObject` and can read/write through the `$` projection.
@MainActor
public final class Preferences: ObservableObject {
    public static let shared = Preferences()

    // MARK: - Stored properties

    @PreferenceStorage("zoom.initialMagnification", default: 2.0)
    public var zoomInitialMagnification: Double

    @PreferenceStorage("zoom.smoothing", default: true)
    public var zoomSmoothing: Bool

    @PreferenceStorage("zoom.animate", default: true)
    public var zoomAnimate: Bool

    @PreferenceStorage("break.durationMinutes", default: 10)
    public var breakDurationMinutes: Int

    @PreferenceStorage("break.lockOnStart", default: false)
    public var breakLockOnStart: Bool

    @PreferenceStorage("break.opacity", default: 1.0)
    public var breakOpacity: Double

    @PreferenceStorage("break.message", default: "Be right back")
    public var breakMessage: String

    @PreferenceStorage("record.format", default: RecordingFormat.mp4.rawValue)
    private var recordFormatRaw: String
    public var recordFormat: RecordingFormat {
        get { RecordingFormat(rawValue: recordFormatRaw) ?? .mp4 }
        set { recordFormatRaw = newValue.rawValue }
    }

    @PreferenceStorage("screenshot.folderPath", default: "")
    private var screenshotFolderPathRaw: String
    public var screenshotFolder: URL {
        get {
            if !screenshotFolderPathRaw.isEmpty {
                return URL(fileURLWithPath: screenshotFolderPathRaw)
            }
            return FileManager.default.urls(for: .desktopDirectory, in: .userDomainMask).first
                ?? URL(fileURLWithPath: NSHomeDirectory()).appendingPathComponent("Desktop")
        }
        set {
            screenshotFolderPathRaw = newValue.path
            objectWillChange.send()
        }
    }

    @PreferenceStorage("onboarding.didComplete", default: false)
    public var didCompleteOnboarding: Bool

    // MARK: - Hotkeys

    private static let hotkeysKey = "hotkeys.bindings.v1"

    private var hotkeyOverrides: [HotkeyAction: HotkeyBinding] = [:]

    private init() {
        loadHotkeys()
    }

    public func binding(for action: HotkeyAction) -> HotkeyBinding? {
        hotkeyOverrides[action] ?? DefaultHotkeys.bindings[action]
    }

    public func setBinding(_ binding: HotkeyBinding?, for action: HotkeyAction) {
        if let binding {
            hotkeyOverrides[action] = binding
        } else {
            hotkeyOverrides.removeValue(forKey: action)
        }
        saveHotkeys()
        objectWillChange.send()
    }

    /// Bulk replacement used by settings import. Persists once and notifies once.
    public func replaceAllHotkeyOverrides(_ overrides: [HotkeyAction: HotkeyBinding]) {
        hotkeyOverrides = overrides
        saveHotkeys()
        objectWillChange.send()
    }

    /// Clears every user override so all actions revert to ``DefaultHotkeys``.
    public func resetHotkeysToDefaults() {
        replaceAllHotkeyOverrides([:])
    }

    /// Snapshot of the *effective* bindings (overrides + defaults filled in).
    /// Used by the recorder UI for conflict detection.
    public func effectiveBindings() -> [HotkeyAction: HotkeyBinding] {
        var result: [HotkeyAction: HotkeyBinding] = [:]
        for action in HotkeyAction.allCases {
            if let b = binding(for: action) {
                result[action] = b
            }
        }
        return result
    }

    private func loadHotkeys() {
        guard let data = UserDefaults.standard.data(forKey: Self.hotkeysKey) else { return }
        do {
            let decoded = try JSONDecoder().decode([String: HotkeyBinding].self, from: data)
            hotkeyOverrides = decoded.reduce(into: [:]) { acc, pair in
                if let action = HotkeyAction(rawValue: pair.key) {
                    acc[action] = pair.value
                }
            }
        } catch {
            NSLog("MacZoomer: failed to decode hotkey overrides: \(error)")
        }
    }

    private func saveHotkeys() {
        let dict = hotkeyOverrides.reduce(into: [String: HotkeyBinding]()) { acc, pair in
            acc[pair.key.rawValue] = pair.value
        }
        do {
            let data = try JSONEncoder().encode(dict)
            UserDefaults.standard.set(data, forKey: Self.hotkeysKey)
        } catch {
            NSLog("MacZoomer: failed to encode hotkey overrides: \(error)")
        }
    }
}

public enum RecordingFormat: String, CaseIterable, Codable, Sendable {
    case mp4
    case gif
}

/// Property wrapper bridging UserDefaults to `@Published`-style updates.
@MainActor
@propertyWrapper
public struct PreferenceStorage<Value> {
    private let key: String
    private let defaultValue: Value
    private let defaults: UserDefaults

    public init(_ key: String, default defaultValue: Value, defaults: UserDefaults = .standard) {
        self.key = key
        self.defaultValue = defaultValue
        self.defaults = defaults
    }

    public var wrappedValue: Value {
        get {
            (defaults.object(forKey: key) as? Value) ?? defaultValue
        }
        nonmutating set {
            defaults.set(newValue, forKey: key)
        }
    }
}
