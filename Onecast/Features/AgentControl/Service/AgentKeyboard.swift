#if DEBUG
import AppKit

/// Posts key events into the app's own queue: the full key path, no global tap, no focus race.
@MainActor
enum AgentKeyboard {
    private static let sentinelSubtype: Int16 = 0x4F43
    /// A sentinel can't be lost, but a modal loop can hold it; never stall a reply past this.
    private static let drainTimeout: Duration = .seconds(2)

    static func press(_ key: AgentKey, in window: NSWindow) async {
        if !window.isKeyWindow { window.makeKey() }
        for type in [NSEvent.EventType.keyDown, .keyUp] {
            guard
                let event = NSEvent.keyEvent(
                    with: type, location: .zero, modifierFlags: flags(key.modifiers),
                    timestamp: ProcessInfo.processInfo.systemUptime,
                    windowNumber: window.windowNumber, context: nil, characters: key.characters,
                    charactersIgnoringModifiers: key.charactersIgnoringModifiers, isARepeat: false,
                    keyCode: key.keyCode)
            else { continue }
            NSApp.postEvent(event, atStart: false)
        }
        await drained()
    }

    /// Resolves once every event posted before it has been dispatched.
    static func drained() async {
        let marker = Int.random(in: 1...Int.max)
        let waiter = SentinelWaiter()
        let monitor = NSEvent.addLocalMonitorForEvents(matching: .applicationDefined) { event in
            guard event.subtype.rawValue == sentinelSubtype, event.data1 == marker else {
                return event
            }
            waiter.finish()
            return nil
        }
        defer { monitor.map(NSEvent.removeMonitor) }
        guard
            let sentinel = NSEvent.otherEvent(
                with: .applicationDefined, location: .zero, modifierFlags: [],
                timestamp: ProcessInfo.processInfo.systemUptime, windowNumber: 0, context: nil,
                subtype: sentinelSubtype, data1: marker, data2: 0)
        else { return }
        NSApp.postEvent(sentinel, atStart: false)
        await waiter.wait(timeout: drainTimeout)
    }

    private static func flags(_ modifiers: AgentKey.Modifiers) -> NSEvent.ModifierFlags {
        var flags: NSEvent.ModifierFlags = []
        if modifiers.contains(.command) { flags.insert(.command) }
        if modifiers.contains(.shift) { flags.insert(.shift) }
        if modifiers.contains(.option) { flags.insert(.option) }
        if modifiers.contains(.control) { flags.insert(.control) }
        if modifiers.contains(.function) { flags.insert(.function) }
        if modifiers.contains(.numericPad) { flags.insert(.numericPad) }
        return flags
    }
}

/// One sentinel's arrival, or the timeout, whichever comes first.
@MainActor
private final class SentinelWaiter {
    private var continuation: CheckedContinuation<Void, Never>?
    private var finished = false

    func wait(timeout: Duration) async {
        guard !finished else { return }
        let timer = Task { [weak self] in
            try? await Task.sleep(for: timeout)
            self?.finish()
        }
        await withCheckedContinuation { continuation = $0 }
        timer.cancel()
    }

    func finish() {
        finished = true
        continuation?.resume()
        continuation = nil
    }
}
#endif
