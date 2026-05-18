import AppKit
import Carbon.HIToolbox

/// Mapping between `kVK_*` virtual key codes and the user-visible glyph or
/// label that should appear in shortcut UI. This is intentionally a single
/// source of truth so the menu equivalents, the hotkey recorder, and the
/// `displayString` on `HotkeyBinding` all agree.
public enum HotkeyKeyNames {

    /// User-facing label for `keyCode`. Returns `nil` when the key isn't
    /// representable as a sensible glyph (modifiers, dead keys, etc.).
    public static func label(for keyCode: UInt16) -> String? {
        if let glyph = glyphs[keyCode] { return glyph }
        if let char = characters[keyCode] { return String(char).uppercased() }
        return nil
    }

    /// `keyEquivalent` string usable on an `NSMenuItem`. We only expose
    /// character keys here — Cocoa's menu item shortcut display handles
    /// modifier glyphs itself, but it expects the raw character of the key.
    public static func menuCharacter(for keyCode: UInt16) -> String? {
        characters[keyCode].map { String($0) }
    }

    /// Plain Latin / digit / symbol keys — used both for menu equivalents
    /// and as a fallback when no special glyph exists for the key.
    private static let characters: [UInt16: Character] = [
        // Digits (top row)
        UInt16(kVK_ANSI_1): "1", UInt16(kVK_ANSI_2): "2", UInt16(kVK_ANSI_3): "3",
        UInt16(kVK_ANSI_4): "4", UInt16(kVK_ANSI_5): "5", UInt16(kVK_ANSI_6): "6",
        UInt16(kVK_ANSI_7): "7", UInt16(kVK_ANSI_8): "8", UInt16(kVK_ANSI_9): "9",
        UInt16(kVK_ANSI_0): "0",
        // Letters
        UInt16(kVK_ANSI_A): "a", UInt16(kVK_ANSI_B): "b", UInt16(kVK_ANSI_C): "c",
        UInt16(kVK_ANSI_D): "d", UInt16(kVK_ANSI_E): "e", UInt16(kVK_ANSI_F): "f",
        UInt16(kVK_ANSI_G): "g", UInt16(kVK_ANSI_H): "h", UInt16(kVK_ANSI_I): "i",
        UInt16(kVK_ANSI_J): "j", UInt16(kVK_ANSI_K): "k", UInt16(kVK_ANSI_L): "l",
        UInt16(kVK_ANSI_M): "m", UInt16(kVK_ANSI_N): "n", UInt16(kVK_ANSI_O): "o",
        UInt16(kVK_ANSI_P): "p", UInt16(kVK_ANSI_Q): "q", UInt16(kVK_ANSI_R): "r",
        UInt16(kVK_ANSI_S): "s", UInt16(kVK_ANSI_T): "t", UInt16(kVK_ANSI_U): "u",
        UInt16(kVK_ANSI_V): "v", UInt16(kVK_ANSI_W): "w", UInt16(kVK_ANSI_X): "x",
        UInt16(kVK_ANSI_Y): "y", UInt16(kVK_ANSI_Z): "z",
        // Symbols (positions on ANSI US)
        UInt16(kVK_ANSI_Minus): "-", UInt16(kVK_ANSI_Equal): "=",
        UInt16(kVK_ANSI_LeftBracket): "[", UInt16(kVK_ANSI_RightBracket): "]",
        UInt16(kVK_ANSI_Backslash): "\\", UInt16(kVK_ANSI_Semicolon): ";",
        UInt16(kVK_ANSI_Quote): "'", UInt16(kVK_ANSI_Comma): ",",
        UInt16(kVK_ANSI_Period): ".", UInt16(kVK_ANSI_Slash): "/",
        UInt16(kVK_ANSI_Grave): "`"
    ]

    /// Keys that show as glyphs (arrows, function keys, etc.) rather than
    /// character output. Mirrors what Cocoa's own shortcut UI displays.
    private static let glyphs: [UInt16: String] = [
        UInt16(kVK_Space):           "Space",
        UInt16(kVK_Tab):             "⇥",
        UInt16(kVK_Return):          "↩",
        UInt16(kVK_ANSI_KeypadEnter):"⌤",
        UInt16(kVK_Escape):          "⎋",
        UInt16(kVK_Delete):          "⌫",
        UInt16(kVK_ForwardDelete):   "⌦",
        UInt16(kVK_Home):            "↖",
        UInt16(kVK_End):             "↘",
        UInt16(kVK_PageUp):          "⇞",
        UInt16(kVK_PageDown):        "⇟",
        UInt16(kVK_LeftArrow):       "←",
        UInt16(kVK_RightArrow):      "→",
        UInt16(kVK_UpArrow):         "↑",
        UInt16(kVK_DownArrow):       "↓",
        UInt16(kVK_F1):  "F1",  UInt16(kVK_F2):  "F2",  UInt16(kVK_F3):  "F3",
        UInt16(kVK_F4):  "F4",  UInt16(kVK_F5):  "F5",  UInt16(kVK_F6):  "F6",
        UInt16(kVK_F7):  "F7",  UInt16(kVK_F8):  "F8",  UInt16(kVK_F9):  "F9",
        UInt16(kVK_F10): "F10", UInt16(kVK_F11): "F11", UInt16(kVK_F12): "F12",
        UInt16(kVK_F13): "F13", UInt16(kVK_F14): "F14", UInt16(kVK_F15): "F15",
        UInt16(kVK_F16): "F16", UInt16(kVK_F17): "F17", UInt16(kVK_F18): "F18",
        UInt16(kVK_F19): "F19", UInt16(kVK_F20): "F20"
    ]
}

extension HotkeyBinding {
    /// User-visible representation: "⌘⇧A", "⌃⌥F5", "⌘Space" …
    public var displayString: String {
        var result = ""
        if modifiers.contains(.control) { result += "⌃" }
        if modifiers.contains(.option)  { result += "⌥" }
        if modifiers.contains(.shift)   { result += "⇧" }
        if modifiers.contains(.command) { result += "⌘" }
        if let label = HotkeyKeyNames.label(for: keyCode) {
            result += label
        } else {
            result += "key#\(keyCode)"
        }
        return result
    }

    /// The plain character used as an `NSMenuItem.keyEquivalent`. Cocoa
    /// renders the modifier glyphs itself based on `keyEquivalentModifierMask`,
    /// so this should be the *character*, not the glyph.
    public var menuKeyEquivalent: String {
        HotkeyKeyNames.menuCharacter(for: keyCode) ?? ""
    }

    public var menuModifierMask: NSEvent.ModifierFlags { modifiers }
}
