import AppKit
import Foundation

/// Identifiers for every globally-registrable action in MacZoomer.
/// Persisted by raw value, so changing a `rawValue` is a breaking change.
public enum HotkeyAction: String, CaseIterable, Codable, Sendable, Identifiable {
    case zoom = "zoom"
    case liveZoom = "live_zoom"
    case draw = "draw"
    case liveDraw = "live_draw"
    case breakTimer = "break_timer"
    case record = "record"
    case recordRegion = "record_region"
    case recordWindow = "record_window"
    case snapshotClipboard = "snapshot_clipboard"
    case snapshotRegionClipboard = "snapshot_region_clipboard"
    case snapshotFile = "snapshot_file"
    case snapshotRegionFile = "snapshot_region_file"

    public var id: String { rawValue }

    public var displayName: String {
        switch self {
        case .zoom: return "Zoom"
        case .liveZoom: return "Live Zoom"
        case .draw: return "Draw"
        case .liveDraw: return "Live Draw"
        case .breakTimer: return "Break Timer"
        case .record: return "Record Screen"
        case .recordRegion: return "Record Region"
        case .recordWindow: return "Record Window"
        case .snapshotClipboard: return "Copy Screenshot"
        case .snapshotRegionClipboard: return "Copy Region Screenshot"
        case .snapshotFile: return "Save Screenshot"
        case .snapshotRegionFile: return "Save Region Screenshot"
        }
    }
}

/// A user-configurable global hotkey: a key plus modifier flags.
public struct HotkeyBinding: Codable, Hashable, Sendable {
    /// A virtual key code as defined by `kVK_*` in Carbon `Events.h`.
    public let keyCode: UInt16
    /// Cocoa-style modifier mask (e.g. `.command`, `.shift`).
    public let modifiers: NSEvent.ModifierFlags

    public init(keyCode: UInt16, modifiers: NSEvent.ModifierFlags) {
        self.keyCode = keyCode
        self.modifiers = modifiers.intersection(.deviceIndependentFlagsMask)
    }

    public static func == (lhs: HotkeyBinding, rhs: HotkeyBinding) -> Bool {
        lhs.keyCode == rhs.keyCode && lhs.modifiers.rawValue == rhs.modifiers.rawValue
    }

    public func hash(into hasher: inout Hasher) {
        hasher.combine(keyCode)
        hasher.combine(modifiers.rawValue)
    }

    enum CodingKeys: String, CodingKey {
        case keyCode
        case modifiers
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        self.keyCode = try container.decode(UInt16.self, forKey: .keyCode)
        let raw = try container.decode(UInt.self, forKey: .modifiers)
        self.modifiers = NSEvent.ModifierFlags(rawValue: raw)
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(keyCode, forKey: .keyCode)
        try container.encode(modifiers.rawValue, forKey: .modifiers)
    }
}

extension HotkeyBinding {
    /// Returns the `keyEquivalent` string for an NSMenuItem, if representable.
    /// We only support a small set of mappings here — the menu shortcut is
    /// purely informational; the real registration goes through Carbon hotkeys.
    public var menuKeyEquivalent: String {
        Self.menuCharacters[keyCode].map(String.init) ?? ""
    }

    public var menuModifierMask: NSEvent.ModifierFlags {
        modifiers
    }

    /// Human-readable form like "⌘1" / "⌘⌥5".
    public var displayString: String {
        var result = ""
        if modifiers.contains(.control) { result += "⌃" }
        if modifiers.contains(.option)  { result += "⌥" }
        if modifiers.contains(.shift)   { result += "⇧" }
        if modifiers.contains(.command) { result += "⌘" }
        if let ch = Self.menuCharacters[keyCode] {
            result += String(ch).uppercased()
        } else {
            result += "key#\(keyCode)"
        }
        return result
    }

    // Small mapping table — enough for the default bindings; expanded as
    // the Phase 7 hotkey-recording UI introduces more keys.
    private static let menuCharacters: [UInt16: Character] = [
        18: "1", 19: "2", 20: "3", 21: "4", 23: "5",
        22: "6", 26: "7", 28: "8", 25: "9", 29: "0"
    ]
}

/// Default bindings, chosen to mirror ZoomIt on Windows but using ⌘ instead
/// of Ctrl so they don't collide with macOS conventions.
public enum DefaultHotkeys {
    public static let bindings: [HotkeyAction: HotkeyBinding] = [
        .zoom:                    .init(keyCode: 18, modifiers: [.command]),               // ⌘1
        .draw:                    .init(keyCode: 19, modifiers: [.command]),               // ⌘2
        .breakTimer:              .init(keyCode: 20, modifiers: [.command]),               // ⌘3
        .liveZoom:                .init(keyCode: 21, modifiers: [.command]),               // ⌘4
        .liveDraw:                .init(keyCode: 21, modifiers: [.command, .shift]),       // ⌘⇧4
        .record:                  .init(keyCode: 23, modifiers: [.command]),               // ⌘5
        .recordRegion:            .init(keyCode: 23, modifiers: [.command, .shift]),       // ⌘⇧5
        .recordWindow:            .init(keyCode: 23, modifiers: [.command, .option]),      // ⌘⌥5
        .snapshotClipboard:       .init(keyCode: 22, modifiers: [.command]),               // ⌘6
        .snapshotRegionClipboard: .init(keyCode: 22, modifiers: [.command, .shift]),       // ⌘⇧6
        .snapshotFile:            .init(keyCode: 22, modifiers: [.command, .control]),     // ⌘⌃6
        .snapshotRegionFile:      .init(keyCode: 22, modifiers: [.command, .shift, .control])
    ]
}
