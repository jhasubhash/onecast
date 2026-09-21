import AppKit
import CoreGraphics
import ScreenCaptureKit

enum ComputerUseError: LocalizedError {
    case screenRecordingDenied
    case accessibilityDenied
    case noDisplay
    case captureFailed
    case unknownKey(String)

    var errorDescription: String? {
        switch self {
        case .screenRecordingDenied:
            return
                "Screen Recording permission is off. Grant Onecast in System Settings › Privacy & "
                + "Security › Screen Recording, then try again."
        case .accessibilityDenied:
            return
                "Accessibility permission is off. Grant Onecast in System Settings › Privacy & "
                + "Security › Accessibility, then try again."
        case .noDisplay:
            return "No display is available to capture."
        case .captureFailed:
            return "The screenshot could not be encoded."
        case .unknownKey(let key):
            return "Unrecognised key \"\(key)\"."
        }
    }
}

/// Screenshots the main display and synthesizes mouse/keyboard events in CGEvent point space.
@MainActor
final class ComputerController {
    struct Shot: Sendable {
        let image: AIImage
        let width: Int
        let height: Int
    }

    /// A grabbed frame plus its logical size, so the tool can tell the model the coordinate space.
    func screenshot() async throws -> Shot {
        guard Permissions.isScreenRecordingTrusted() else {
            Permissions.ensureScreenRecording()
            throw ComputerUseError.screenRecordingDenied
        }
        let content = try await SCShareableContent.excludingDesktopWindows(
            false, onScreenWindowsOnly: false)
        guard
            let display = content.displays.first(where: { $0.displayID == CGMainDisplayID() })
                ?? content.displays.first
        else { throw ComputerUseError.noDisplay }
        let filter = SCContentFilter(display: display, excludingWindows: [])
        let config = SCStreamConfiguration()
        config.width = display.width
        config.height = display.height
        config.showsCursor = true
        let cgImage = try await SCScreenshotManager.captureImage(
            contentFilter: filter, configuration: config)
        guard let data = Self.jpeg(from: cgImage) else { throw ComputerUseError.captureFailed }
        return Shot(
            image: AIImage(data: data, mimeType: "image/jpeg"),
            width: display.width, height: display.height)
    }

    func move(to point: CGPoint) async throws {
        try requireInput()
        post(.mouseMoved, at: point, button: .left)
    }

    func click(at point: CGPoint, button: CGMouseButton, count: Int) async throws {
        try requireInput()
        let (down, up): (CGEventType, CGEventType) =
            button == .right ? (.rightMouseDown, .rightMouseUp) : (.leftMouseDown, .leftMouseUp)
        for clickState in 1...max(1, count) {
            post(down, at: point, button: button, clickState: clickState)
            post(up, at: point, button: button, clickState: clickState)
            try? await Task.sleep(for: .milliseconds(20))
        }
    }

    func drag(from start: CGPoint, to end: CGPoint) async throws {
        try requireInput()
        post(.leftMouseDown, at: start, button: .left)
        let steps = 12
        for step in 1...steps {
            let t = CGFloat(step) / CGFloat(steps)
            let point = CGPoint(
                x: start.x + (end.x - start.x) * t, y: start.y + (end.y - start.y) * t)
            post(.leftMouseDragged, at: point, button: .left)
            try? await Task.sleep(for: .milliseconds(12))
        }
        post(.leftMouseUp, at: end, button: .left)
    }

    func scroll(at point: CGPoint, dx: Int, dy: Int) async throws {
        try requireInput()
        post(.mouseMoved, at: point, button: .left)
        CGEvent(
            scrollWheelEvent2Source: nil, units: .pixel, wheelCount: 2,
            wheel1: Int32(dy), wheel2: Int32(dx), wheel3: 0)?
            .post(tap: .cghidEventTap)
    }

    func type(_ text: String) async throws {
        try requireInput()
        for character in text {
            var units = Array(String(character).utf16)
            let down = CGEvent(keyboardEventSource: nil, virtualKey: 0, keyDown: true)
            down?.keyboardSetUnicodeString(stringLength: units.count, unicodeString: &units)
            down?.post(tap: .cghidEventTap)
            let up = CGEvent(keyboardEventSource: nil, virtualKey: 0, keyDown: false)
            up?.keyboardSetUnicodeString(stringLength: units.count, unicodeString: &units)
            up?.post(tap: .cghidEventTap)
            try? await Task.sleep(for: .milliseconds(6))
        }
    }

    /// A chord like "cmd+shift+k", or a lone named key like "return", "tab", "escape", "left".
    func key(_ combo: String) async throws {
        try requireInput()
        var flags: CGEventFlags = []
        var keyName: String?
        for part in combo.lowercased().split(separator: "+").map(String.init) {
            switch part {
            case "cmd", "command", "⌘": flags.insert(.maskCommand)
            case "shift", "⇧": flags.insert(.maskShift)
            case "opt", "option", "alt", "⌥": flags.insert(.maskAlternate)
            case "ctrl", "control", "⌃": flags.insert(.maskControl)
            case "fn": flags.insert(.maskSecondaryFn)
            default: keyName = part
            }
        }
        guard let keyName, let code = Self.keyCodes[keyName] else {
            throw ComputerUseError.unknownKey(keyName ?? combo)
        }
        let down = CGEvent(keyboardEventSource: nil, virtualKey: code, keyDown: true)
        down?.flags = flags
        down?.post(tap: .cghidEventTap)
        let up = CGEvent(keyboardEventSource: nil, virtualKey: code, keyDown: false)
        up?.flags = flags
        up?.post(tap: .cghidEventTap)
    }

    private func requireInput() throws {
        guard Permissions.isAccessibilityTrusted() else {
            Permissions.ensureAccessibility()
            throw ComputerUseError.accessibilityDenied
        }
    }

    private func post(
        _ type: CGEventType, at point: CGPoint, button: CGMouseButton, clickState: Int = 1
    ) {
        guard
            let event = CGEvent(
                mouseEventSource: nil, mouseType: type, mouseCursorPosition: point,
                mouseButton: button)
        else { return }
        if clickState > 1 { event.setIntegerValueField(.mouseEventClickState, value: Int64(clickState)) }
        event.post(tap: .cghidEventTap)
    }

    private static func jpeg(from cgImage: CGImage) -> Data? {
        NSBitmapImageRep(cgImage: cgImage)
            .representation(using: .jpeg, properties: [.compressionFactor: 0.6])
    }

    /// ANSI virtual keycodes: letters and digits for shortcuts, plus the editing and arrow keys.
    private static let keyCodes: [String: CGKeyCode] = [
        "a": 0, "s": 1, "d": 2, "f": 3, "h": 4, "g": 5, "z": 6, "x": 7, "c": 8, "v": 9,
        "b": 11, "q": 12, "w": 13, "e": 14, "r": 15, "y": 16, "t": 17, "o": 31, "u": 32,
        "i": 34, "p": 35, "l": 37, "j": 38, "k": 40, "n": 45, "m": 46,
        "1": 18, "2": 19, "3": 20, "4": 21, "6": 22, "5": 23, "9": 25, "7": 26, "8": 28, "0": 29,
        "=": 24, "-": 27, "]": 30, "[": 33, "'": 39, ";": 41, "\\": 42, ",": 43, "/": 44,
        ".": 47, "`": 50,
        "return": 36, "enter": 76, "tab": 48, "space": 49, "delete": 51, "backspace": 51,
        "escape": 53, "esc": 53, "forwarddelete": 117,
        "left": 123, "right": 124, "down": 125, "up": 126,
        "home": 115, "end": 119, "pageup": 116, "pagedown": 121,
    ]
}
