import Foundation

extension Process {
    /// Use instead of `waitUntilExit`, whose run loop can miss the exit on a GCD thread and hang.
    func runObservingExit() throws -> ProcessExit {
        let exit = ProcessExit()
        terminationHandler = { _ in exit.signal() }
        try run()
        return exit
    }
}

/// Blocks without a run loop, and every wait after the exit returns at once.
struct ProcessExit: Sendable {
    private let semaphore = DispatchSemaphore(value: 0)

    fileprivate func signal() {
        semaphore.signal()
    }

    func wait() {
        semaphore.wait()
        semaphore.signal()
    }

    /// False when the deadline passes first; a nil deadline waits for the exit.
    func wait(until deadline: DispatchTime?) -> Bool {
        guard let deadline else {
            wait()
            return true
        }
        guard semaphore.wait(timeout: deadline) == .success else { return false }
        semaphore.signal()
        return true
    }
}
