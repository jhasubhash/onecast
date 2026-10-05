/// A sleep an event can cut short, so a sampler ticks on schedule and early on a signal.
@MainActor
final class SystemPacer {
    private var sleeper: Task<Void, Never>?
    /// A wake that lands while the sampler is busy, so the next wait returns at once.
    private var wakePending = false

    func wait(_ duration: Duration) async {
        if wakePending {
            wakePending = false
            return
        }
        let sleeper = Task { _ = try? await Task.sleep(for: duration) }
        self.sleeper = sleeper
        await withTaskCancellationHandler {
            await sleeper.value
        } onCancel: {
            sleeper.cancel()
        }
        wakePending = false
    }

    func wake() {
        wakePending = true
        sleeper?.cancel()
    }
}
