import AppKit
import Combine

/// Full-screen view rendering the break-timer countdown: a large
/// monospaced digit clock with an optional message line below.
final class BreakTimerView: NSView {
    let state: BreakTimerState
    private let message: String
    private let opacity: CGFloat

    private let timeLabel = NSTextField(labelWithString: "")
    private let messageLabel = NSTextField(labelWithString: "")
    private let endedLabel = NSTextField(labelWithString: "")

    private var observers = Set<AnyCancellable>()

    init(frame: NSRect, state: BreakTimerState, message: String, opacity: CGFloat) {
        self.state = state
        self.message = message
        self.opacity = max(0.05, min(1.0, opacity))
        super.init(frame: frame)
        wantsLayer = true
        layer?.backgroundColor = NSColor.black.withAlphaComponent(self.opacity).cgColor

        configureTimeLabel()
        configureMessageLabel()
        configureEndedLabel()

        addSubview(timeLabel)
        addSubview(messageLabel)
        addSubview(endedLabel)

        NSLayoutConstraint.activate([
            timeLabel.centerXAnchor.constraint(equalTo: centerXAnchor),
            timeLabel.centerYAnchor.constraint(equalTo: centerYAnchor),

            messageLabel.centerXAnchor.constraint(equalTo: centerXAnchor),
            messageLabel.topAnchor.constraint(equalTo: timeLabel.bottomAnchor, constant: 40),
            messageLabel.leadingAnchor.constraint(greaterThanOrEqualTo: leadingAnchor, constant: 40),
            messageLabel.trailingAnchor.constraint(lessThanOrEqualTo: trailingAnchor, constant: -40),

            endedLabel.centerXAnchor.constraint(equalTo: centerXAnchor),
            endedLabel.bottomAnchor.constraint(equalTo: timeLabel.topAnchor, constant: -40)
        ])

        observe()
        updateRemaining(state.remaining)
        updateFinished(state.didFinish)
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    private func configureTimeLabel() {
        timeLabel.font = NSFont.monospacedDigitSystemFont(ofSize: 240, weight: .bold)
        timeLabel.textColor = NSColor.white
        timeLabel.alignment = .center
        timeLabel.translatesAutoresizingMaskIntoConstraints = false
        timeLabel.isBezeled = false
        timeLabel.isEditable = false
        timeLabel.drawsBackground = false
    }

    private func configureMessageLabel() {
        messageLabel.stringValue = message
        messageLabel.font = NSFont.systemFont(ofSize: 36, weight: .medium)
        messageLabel.textColor = NSColor.white.withAlphaComponent(0.75)
        messageLabel.alignment = .center
        messageLabel.translatesAutoresizingMaskIntoConstraints = false
        messageLabel.isBezeled = false
        messageLabel.isEditable = false
        messageLabel.drawsBackground = false
        messageLabel.maximumNumberOfLines = 2
        messageLabel.lineBreakMode = .byWordWrapping
    }

    private func configureEndedLabel() {
        endedLabel.stringValue = ""
        endedLabel.font = NSFont.systemFont(ofSize: 28, weight: .semibold)
        endedLabel.textColor = NSColor.systemGreen
        endedLabel.alignment = .center
        endedLabel.translatesAutoresizingMaskIntoConstraints = false
        endedLabel.isBezeled = false
        endedLabel.isEditable = false
        endedLabel.drawsBackground = false
    }

    private func observe() {
        state.$remaining
            .receive(on: RunLoop.main)
            .sink { [weak self] remaining in self?.updateRemaining(remaining) }
            .store(in: &observers)
        state.$didFinish
            .receive(on: RunLoop.main)
            .sink { [weak self] finished in self?.updateFinished(finished) }
            .store(in: &observers)
        state.$isRunning
            .receive(on: RunLoop.main)
            .sink { [weak self] running in self?.updateRunning(running) }
            .store(in: &observers)
    }

    private func updateRemaining(_ seconds: TimeInterval) {
        timeLabel.stringValue = BreakTimerFormatter.string(from: seconds)
    }

    private func updateFinished(_ finished: Bool) {
        endedLabel.stringValue = finished ? "Time's up — press Esc to dismiss" : ""
        timeLabel.textColor = finished ? NSColor.systemGreen : NSColor.white
    }

    private func updateRunning(_ running: Bool) {
        if state.didFinish { return }
        timeLabel.textColor = running ? NSColor.white : NSColor.systemYellow
    }
}
