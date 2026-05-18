import AppKit
import Foundation

/// On-disk shape of the settings export. Versioned so future schema changes
/// can detect older files and decode them via dedicated paths instead of
/// silently dropping unknown fields.
struct SettingsExportV1: Codable {
    var version: Int = 1
    var preferences: PreferencesPayload
    var hotkeys: [String: HotkeyBinding]

    struct PreferencesPayload: Codable {
        var zoomInitialMagnification: Double
        var zoomSmoothing: Bool
        var zoomAnimate: Bool
        var breakDurationMinutes: Int
        var breakLockOnStart: Bool
        var breakOpacity: Double
        var breakMessage: String
        var recordFormat: String
        var screenshotFolder: String?
    }
}

extension Preferences {

    /// Encodes every user-visible preference plus all hotkey overrides into a
    /// pretty-printed JSON blob suitable for writing to disk or copying.
    public func exportToData() throws -> Data {
        let payload = SettingsExportV1.PreferencesPayload(
            zoomInitialMagnification: zoomInitialMagnification,
            zoomSmoothing: zoomSmoothing,
            zoomAnimate: zoomAnimate,
            breakDurationMinutes: breakDurationMinutes,
            breakLockOnStart: breakLockOnStart,
            breakOpacity: breakOpacity,
            breakMessage: breakMessage,
            recordFormat: recordFormat.rawValue,
            screenshotFolder: screenshotFolder.path
        )

        var hotkeysDict: [String: HotkeyBinding] = [:]
        for action in HotkeyAction.allCases {
            if let b = binding(for: action) {
                hotkeysDict[action.rawValue] = b
            }
        }

        let export = SettingsExportV1(preferences: payload, hotkeys: hotkeysDict)
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        return try encoder.encode(export)
    }

    /// Replaces the current preferences with the contents of `data`. Performs
    /// minimal sanity-clamping (magnification 1.0–8.0, opacity 0.1–1.0) and
    /// silently drops hotkey entries whose `HotkeyAction` no longer exists.
    public func importFromData(_ data: Data) throws {
        let export = try JSONDecoder().decode(SettingsExportV1.self, from: data)
        let p = export.preferences

        zoomInitialMagnification = max(1.0, min(8.0, p.zoomInitialMagnification))
        zoomSmoothing            = p.zoomSmoothing
        zoomAnimate              = p.zoomAnimate
        breakDurationMinutes     = max(1, min(240, p.breakDurationMinutes))
        breakLockOnStart         = p.breakLockOnStart
        breakOpacity             = max(0.1, min(1.0, p.breakOpacity))
        breakMessage             = p.breakMessage
        if let format = RecordingFormat(rawValue: p.recordFormat) {
            recordFormat = format
        }
        if let folder = p.screenshotFolder, !folder.isEmpty {
            screenshotFolder = URL(fileURLWithPath: folder)
        }

        var overrides: [HotkeyAction: HotkeyBinding] = [:]
        for (key, binding) in export.hotkeys {
            if let action = HotkeyAction(rawValue: key) {
                overrides[action] = binding
            }
        }
        replaceAllHotkeyOverrides(overrides)

        objectWillChange.send()
    }
}
