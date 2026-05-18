import Combine
import Foundation

/// In-memory state for an active break-timer session: the countdown and
/// whether it's running / paused / finished.
///
/// All public mutators are MainActor-isolated so SwiftUI/AppKit views can
/// observe via `@Published` without thread hops.
@MainActor
public final class BreakTimerState: ObservableObject {
    /// Total break duration the timer was started with — used when the user
    /// hits "reset" during the break.
    public let initialDuration: TimeInterval

    /// Seconds remaining. Counts down once per second when running.
    @Published public private(set) var remaining: TimeInterval

    @Published public private(set) var isRunning: Bool = false

    /// Set true the moment `remaining` hits zero. Stays true until the
    /// timer is reset or the session ends.
    @Published public private(set) var didFinish: Bool = false

    private var timer: Timer?

    public init(initialDuration: TimeInterval) {
        self.initialDuration = max(0, initialDuration)
        self.remaining = self.initialDuration
    }

    deinit {
        timer?.invalidate()
    }

    public func start() {
        guard !isRunning, remaining > 0 else { return }
        isRunning = true
        scheduleTick()
    }

    public func pause() {
        timer?.invalidate()
        timer = nil
        isRunning = false
    }

    public func toggle() {
        if isRunning {
            pause()
        } else {
            start()
        }
    }

    /// Reverts the timer to its starting duration and stops ticking.
    public func reset() {
        pause()
        remaining = initialDuration
        didFinish = false
    }

    /// Adds (or, with a negative value, subtracts) seconds from `remaining`.
    /// Clamps at zero. If the timer was paused, the running state is left
    /// unchanged; the caller decides whether to resume.
    public func adjust(by delta: TimeInterval) {
        remaining = max(0, remaining + delta)
        if remaining > 0 {
            didFinish = false
        } else if !didFinish {
            didFinish = true
            pause()
        }
    }

    public func setRemaining(_ value: TimeInterval) {
        remaining = max(0, value)
        if remaining == 0 && !didFinish {
            didFinish = true
            pause()
        }
    }

    private func scheduleTick() {
        timer?.invalidate()
        // Timer fires on the main runloop; the Task hop is needed only so
        // the Swift 6 compiler can prove MainActor isolation.
        timer = Timer.scheduledTimer(withTimeInterval: 1.0, repeats: true) { [weak self] _ in
            Task { @MainActor [weak self] in self?.tick() }
        }
    }

    private func tick() {
        guard isRunning else { return }
        remaining = max(0, remaining - 1)
        if remaining == 0 {
            didFinish = true
            pause()
        }
    }
}

public enum BreakTimerFormatter {
    /// Returns a `M:SS` string for the given remaining seconds.
    /// Anything over an hour is formatted as `H:MM:SS`.
    public static func string(from seconds: TimeInterval) -> String {
        let total = Int(ceil(max(0, seconds)))
        let h = total / 3600
        let m = (total % 3600) / 60
        let s = total % 60
        if h > 0 {
            return String(format: "%d:%02d:%02d", h, m, s)
        }
        return String(format: "%d:%02d", m, s)
    }
}
