import AppKit

/// Top-level controller for the break-timer overlay (the ZoomIt
/// "Break Timer" feature — a full-screen countdown shown to the
/// audience while the presenter is away).
///
/// Spans every connected display, ticks down from a configurable
/// duration, supports pause/resume (Space), adjust (arrows), and
/// reset (R). Exits on Esc or right-click.
@MainActor
public final class BreakTimerMode: ObservableObject {
    private let preferences: Preferences

    private(set) var state: BreakTimerState?
    private var windows: [BreakTimerWindow] = []
    public private(set) var isActive = false

    public init(preferences: Preferences) {
        self.preferences = preferences
    }

    public func activate() {
        guard !isActive else { return }
        isActive = true

        let durationSeconds = TimeInterval(max(1, preferences.breakDurationMinutes) * 60)
        let message = preferences.breakMessage
        let opacity = CGFloat(preferences.breakOpacity)
        let state = BreakTimerState(initialDuration: durationSeconds)
        self.state = state

        for screen in NSScreen.screens {
            let window = BreakTimerWindow(
                screen: screen,
                state: state,
                message: message,
                opacity: opacity
            )
            wireUp(window: window, state: state)
            window.makeKeyAndOrderFront(nil as AnyObject?)
            windows.append(window)
        }

        state.start()
    }

    public func deactivate() {
        guard isActive else { return }
        isActive = false
        state?.pause()
        state = nil
        for window in windows {
            window.orderOut(nil)
        }
        windows.removeAll()
    }

    private func wireUp(window: BreakTimerWindow, state: BreakTimerState) {
        window.onExit = { [weak self] in self?.deactivate() }
        window.onTogglePause = { [weak state] in state?.toggle() }
        window.onAdjust = { [weak state] delta in state?.adjust(by: delta) }
        window.onReset = { [weak state] in
            guard let state else { return }
            let wasRunning = state.isRunning
            state.reset()
            if wasRunning { state.start() }
        }
    }
}
