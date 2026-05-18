import AppKit
import Carbon.HIToolbox
import Combine

/// Registers and dispatches global hotkeys via the Carbon Hot Key API.
/// Carbon is deprecated for general use but `RegisterEventHotKey` is still
/// the official mechanism for app-wide hotkeys without Accessibility.
@MainActor
public final class HotkeyManager: ObservableObject {
    public typealias Handler = @MainActor (HotkeyAction) -> Void

    private let preferences: Preferences
    private var registrations: [HotkeyAction: EventHotKeyRef] = [:]
    private var hotKeyIDByAction: [HotkeyAction: UInt32] = [:]
    private var actionByHotKeyID: [UInt32: HotkeyAction] = [:]
    private var eventHandlerRef: EventHandlerRef?
    private var nextHotKeyID: UInt32 = 1
    private var handler: Handler?
    private var prefsCancellable: AnyCancellable?

    /// Four-char-code 'MZmr' — Carbon expects a signature for hot key IDs.
    private static let signature: OSType = {
        let chars: [Character] = ["M", "Z", "m", "r"]
        return chars.reduce(0) { acc, ch in
            (acc << 8) | OSType(ch.asciiValue ?? 0)
        }
    }()

    public init(preferences: Preferences) {
        self.preferences = preferences
        installEventHandler()

        prefsCancellable = preferences.objectWillChange
            .receive(on: RunLoop.main)
            .sink { [weak self] _ in
                Task { @MainActor in self?.registerAll() }
            }
    }

    deinit {
        // EventHotKeyRef removal must happen on the main thread; we rely on
        // unregisterAll() being called from applicationWillTerminate.
        if let ref = eventHandlerRef {
            RemoveEventHandler(ref)
        }
    }

    public func setHandler(_ handler: @escaping Handler) {
        self.handler = handler
    }

    public func registerAll() {
        unregisterAll()
        for action in HotkeyAction.allCases {
            guard let binding = preferences.binding(for: action) else { continue }
            register(action: action, binding: binding)
        }
    }

    public func unregisterAll() {
        for (_, ref) in registrations {
            UnregisterEventHotKey(ref)
        }
        registrations.removeAll()
        hotKeyIDByAction.removeAll()
        actionByHotKeyID.removeAll()
    }

    private func register(action: HotkeyAction, binding: HotkeyBinding) {
        let id = nextHotKeyID
        nextHotKeyID += 1
        let hotKeyID = EventHotKeyID(signature: Self.signature, id: id)
        var ref: EventHotKeyRef?
        let status = RegisterEventHotKey(
            UInt32(binding.keyCode),
            carbonModifiers(from: binding.modifiers),
            hotKeyID,
            GetApplicationEventTarget(),
            0,
            &ref
        )
        guard status == noErr, let ref else {
            NSLog("MacZoomer: failed to register hotkey for \(action.rawValue) (status \(status))")
            return
        }
        registrations[action] = ref
        hotKeyIDByAction[action] = id
        actionByHotKeyID[id] = action
    }

    private func installEventHandler() {
        var spec = EventTypeSpec(eventClass: OSType(kEventClassKeyboard),
                                 eventKind: UInt32(kEventHotKeyPressed))
        let selfPtr = Unmanaged.passUnretained(self).toOpaque()
        InstallEventHandler(
            GetApplicationEventTarget(),
            { _, eventRef, userData -> OSStatus in
                guard let eventRef, let userData else { return noErr }
                var hotKeyID = EventHotKeyID()
                let status = GetEventParameter(
                    eventRef,
                    EventParamName(kEventParamDirectObject),
                    EventParamType(typeEventHotKeyID),
                    nil,
                    MemoryLayout<EventHotKeyID>.size,
                    nil,
                    &hotKeyID
                )
                guard status == noErr else { return status }
                let manager = Unmanaged<HotkeyManager>.fromOpaque(userData).takeUnretainedValue()
                Task { @MainActor in
                    manager.handleHotKey(id: hotKeyID.id)
                }
                return noErr
            },
            1,
            &spec,
            selfPtr,
            &eventHandlerRef
        )
    }

    @MainActor
    private func handleHotKey(id: UInt32) {
        guard let action = actionByHotKeyID[id] else { return }
        handler?(action)
    }

    private func carbonModifiers(from cocoa: NSEvent.ModifierFlags) -> UInt32 {
        var result: UInt32 = 0
        if cocoa.contains(.command) { result |= UInt32(cmdKey) }
        if cocoa.contains(.option)  { result |= UInt32(optionKey) }
        if cocoa.contains(.control) { result |= UInt32(controlKey) }
        if cocoa.contains(.shift)   { result |= UInt32(shiftKey) }
        return result
    }
}
