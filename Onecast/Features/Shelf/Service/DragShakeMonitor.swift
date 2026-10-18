import AppKit

/// Watches every left-button drag for a shake, but only while the drag carries something.
@MainActor
final class DragShakeMonitor {
    var onShake: (() -> Void)?

    private var monitors: [Any] = []
    private var detector = ShakeDetector()
    private var dragChangeCount = 0
    private var fired = false

    var isRunning: Bool { !monitors.isEmpty }

    func start() {
        guard monitors.isEmpty else { return }
        let mask: NSEvent.EventTypeMask = [.leftMouseDown, .leftMouseDragged, .leftMouseUp]
        let global = NSEvent.addGlobalMonitorForEvents(matching: mask) { [weak self] event in
            MainActor.assumeIsolated { self?.handle(event) }
        }
        let local = NSEvent.addLocalMonitorForEvents(matching: mask) { [weak self] event in
            self?.handle(event)
            return event
        }
        monitors = [global, local].compactMap { $0 }
    }

    func stop() {
        monitors.forEach(NSEvent.removeMonitor)
        monitors = []
        detector.reset()
    }

    private func handle(_ event: NSEvent) {
        switch event.type {
        case .leftMouseDown:
            detector.reset()
            fired = false
            dragChangeCount = NSPasteboard(name: .drag).changeCount
        case .leftMouseDragged:
            // A window move or text selection never writes the drag pasteboard; a real drag does.
            guard !fired, NSPasteboard(name: .drag).changeCount != dragChangeCount else { return }
            if detector.record(x: NSEvent.mouseLocation.x, at: event.timestamp) {
                fired = true
                onShake?()
            }
        default:
            detector.reset()
        }
    }
}
