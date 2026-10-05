/// One widget instance's claim on a shared sampler; the sampler runs only while claims exist.
@MainActor
final class SystemSamplerLease {
    private var release: (@MainActor () -> Void)?

    init(release: @escaping @MainActor () -> Void) {
        self.release = release
    }

    /// Idempotent, so `didRemove` and a later deinit never release the sampler twice.
    func end() {
        release?()
        release = nil
    }

    isolated deinit {
        end()
    }
}
