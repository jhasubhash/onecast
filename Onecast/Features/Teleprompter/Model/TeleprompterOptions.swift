import Foundation

/// How the prompter moves through the script.
enum TeleprompterMode: String, CaseIterable, Identifiable, Sendable {
    /// Follows the speaker word by word through speech recognition.
    case wordTracking
    /// Scrolls at a steady pace with no microphone.
    case classic
    /// Scrolls at that pace only while the speaker's voice is heard.
    case voiceActivated

    var id: String { rawValue }

    var title: String {
        switch self {
        case .wordTracking: "Word Tracking"
        case .classic: "Classic"
        case .voiceActivated: "Voice-Activated"
        }
    }

    var usesMicrophone: Bool { self != .classic }
}

/// Where the prompter sits.
enum TeleprompterPlacement: String, CaseIterable, Identifiable, Sendable {
    /// Hangs from the top of the screen, under the notch where there is one.
    case notch
    /// A window the speaker drags anywhere.
    case floating

    var id: String { rawValue }

    var title: String {
        switch self {
        case .notch: "Below the Notch"
        case .floating: "Floating Window"
        }
    }
}

enum TeleprompterHighlight: String, CaseIterable, Identifiable, Sendable {
    case yellow, green, blue, pink, orange, white

    var id: String { rawValue }
    var title: String { rawValue.capitalized }
}

enum TeleprompterPace {
    /// Words per minute: a slow, careful read up to a fast one.
    static let range = 60...300
    static let standard = 140
    static let textSizes = 16...44
    static let standardTextSize = 24
}
