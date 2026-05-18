import AppKit
import Carbon.HIToolbox
import SwiftUI

/// SwiftUI hotkey recorder. Click to activate, then press a chord; the next
/// `keyDown` with at least one modifier commits. `Esc` cancels; `Delete`
/// (Backspace) without modifiers clears the binding back to its default.
///
/// While recording we temporarily ``HotkeyManager.pauseGlobalHotkeys()`` so
/// the user's current bindings (e.g. ⌘1) don't fire their action mid-press —
/// the recorder is meant to *capture* the chord, not trigger it.
struct HotkeyRecorderView: View {
    let action: HotkeyAction
    @EnvironmentObject private var preferences: Preferences
    @EnvironmentObject private var hotkeys: HotkeyManager

    @State private var isRecording = false
    @State private var monitor: Any?
    @State private var liveModifiers: NSEvent.ModifierFlags = []
    @State private var conflictMessage: String?

    var body: some View {
        HStack(spacing: 6) {
            Button(action: toggleRecording) {
                HStack(spacing: 0) {
                    Text(displayText)
                        .monospaced()
                        .foregroundStyle(isRecording ? .secondary : .primary)
                        .frame(minWidth: 110, alignment: .center)
                }
                .padding(.horizontal, 8)
                .padding(.vertical, 4)
                .background(
                    RoundedRectangle(cornerRadius: 5)
                        .stroke(isRecording ? Color.accentColor : Color.secondary.opacity(0.4),
                                lineWidth: isRecording ? 2 : 1)
                )
            }
            .buttonStyle(.plain)
            .help("Click and press a shortcut. Esc cancels, Delete clears.")

            Button {
                preferences.setBinding(nil, for: action)
            } label: {
                Image(systemName: "arrow.uturn.backward")
            }
            .buttonStyle(.borderless)
            .help("Reset to default")
            .disabled(preferences.effectiveBindings()[action] == DefaultHotkeys.bindings[action]
                      && !hasOverride)

            if let conflictMessage {
                Text(conflictMessage)
                    .font(.caption)
                    .foregroundStyle(.orange)
                    .transition(.opacity)
            }
        }
        .onDisappear { stopRecording() }
    }

    private var hasOverride: Bool {
        // Compares effective binding against default — used to enable the
        // reset button only when the user has actually customized this slot.
        let effective = preferences.binding(for: action)
        return effective != DefaultHotkeys.bindings[action]
    }

    private var displayText: String {
        if isRecording {
            return liveModifiers.isEmpty ? "Press shortcut…" : modifiersGlyphs(liveModifiers) + "…"
        }
        return preferences.binding(for: action)?.displayString ?? "—"
    }

    private func modifiersGlyphs(_ flags: NSEvent.ModifierFlags) -> String {
        var result = ""
        if flags.contains(.control) { result += "⌃" }
        if flags.contains(.option)  { result += "⌥" }
        if flags.contains(.shift)   { result += "⇧" }
        if flags.contains(.command) { result += "⌘" }
        return result
    }

    private func toggleRecording() {
        if isRecording {
            stopRecording()
        } else {
            startRecording()
        }
    }

    private func startRecording() {
        conflictMessage = nil
        liveModifiers = []
        isRecording = true
        hotkeys.pauseGlobalHotkeys()
        monitor = NSEvent.addLocalMonitorForEvents(matching: [.keyDown, .flagsChanged]) { event in
            handle(event: event)
        }
    }

    private func stopRecording() {
        if let monitor {
            NSEvent.removeMonitor(monitor)
            self.monitor = nil
        }
        if isRecording {
            hotkeys.resumeGlobalHotkeys()
        }
        isRecording = false
        liveModifiers = []
    }

    /// Returns nil when consuming an event, or the original event when we
    /// want AppKit to keep processing it. Inside the settings window we
    /// always consume during recording so the event doesn't reach beep'ing
    /// responders.
    private func handle(event: NSEvent) -> NSEvent? {
        guard isRecording else { return event }
        let modifiers = event.modifierFlags.intersection(.deviceIndependentFlagsMask)

        switch event.type {
        case .flagsChanged:
            liveModifiers = modifiers
            return nil

        case .keyDown:
            let keyCode = event.keyCode

            if keyCode == UInt16(kVK_Escape) && modifiers.isEmpty {
                stopRecording()
                return nil
            }
            if (keyCode == UInt16(kVK_Delete) || keyCode == UInt16(kVK_ForwardDelete))
                && modifiers.isEmpty {
                preferences.setBinding(nil, for: action)
                stopRecording()
                return nil
            }

            // Modifier-only chord — wait for a real key.
            if !hasUsableModifier(modifiers) {
                showTransientConflict("Use at least one modifier (⌘, ⌥, ⌃ or ⇧).")
                return nil
            }

            let candidate = HotkeyBinding(keyCode: keyCode, modifiers: modifiers)

            // Conflict: same chord already bound to a different action.
            if let owner = conflictOwner(of: candidate) {
                showTransientConflict("Already used by \(owner.displayName).")
                return nil
            }

            preferences.setBinding(candidate, for: action)
            stopRecording()
            return nil

        default:
            return event
        }
    }

    private func hasUsableModifier(_ flags: NSEvent.ModifierFlags) -> Bool {
        flags.contains(.command) || flags.contains(.option) ||
        flags.contains(.control) || flags.contains(.shift)
    }

    private func conflictOwner(of candidate: HotkeyBinding) -> HotkeyAction? {
        let effective = preferences.effectiveBindings()
        for (otherAction, otherBinding) in effective where otherAction != action {
            if otherBinding == candidate { return otherAction }
        }
        return nil
    }

    private func showTransientConflict(_ message: String) {
        conflictMessage = message
        let snapshot = message
        DispatchQueue.main.asyncAfter(deadline: .now() + 2.5) {
            if conflictMessage == snapshot {
                conflictMessage = nil
            }
        }
    }
}
