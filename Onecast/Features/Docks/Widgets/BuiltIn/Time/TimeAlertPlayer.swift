import AppKit

/// Plays the system alert sound for a time widget, once or on a repeat until it is stopped.
@MainActor
final class TimeAlertPlayer {
    private static let soundName = "Glass"
    private static let repeatInterval: Duration = .seconds(3)
    /// A ringing alarm nobody answers falls silent after this many chimes.
    private static let repeatLimit = 10

    private var repeater: Task<Void, Never>?

    func chime() {
        guard let sound = NSSound(named: Self.soundName) else { return }
        sound.stop()
        sound.play()
    }

    func chimeRepeatedly() {
        stop()
        repeater = Task { [weak self] in
            for _ in 0..<Self.repeatLimit {
                guard let self, !Task.isCancelled else { return }
                chime()
                try? await Task.sleep(for: Self.repeatInterval)
            }
        }
    }

    func stop() {
        repeater?.cancel()
        repeater = nil
        NSSound(named: Self.soundName)?.stop()
    }

    isolated deinit {
        repeater?.cancel()
    }
}
