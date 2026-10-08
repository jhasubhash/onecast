import Foundation

/// A key press described in data, turned into an `NSEvent` by the caller.
struct AgentKey: Equatable, Sendable {
    struct Modifiers: OptionSet, Equatable, Sendable {
        let rawValue: Int
        static let command = Modifiers(rawValue: 1 << 0)
        static let shift = Modifiers(rawValue: 1 << 1)
        static let option = Modifiers(rawValue: 1 << 2)
        static let control = Modifiers(rawValue: 1 << 3)
        static let function = Modifiers(rawValue: 1 << 4)
        static let numericPad = Modifiers(rawValue: 1 << 5)
    }

    enum ParseError: Error, Equatable, LocalizedError {
        case unknownKey(String)
        case unknownModifier(String)

        var errorDescription: String? {
            switch self {
            case .unknownKey(let key): return "Unknown key \"\(key)\"."
            case .unknownModifier(let modifier): return "Unknown modifier \"\(modifier)\"."
            }
        }
    }

    let keyCode: UInt16
    let characters: String
    let charactersIgnoringModifiers: String
    let modifiers: Modifiers

    /// `"down"`, `"return"`, `"k"`, `"cmd+k"`, `"ctrl+shift+n"`, `"⌘,"`.
    static func parse(_ chord: String) throws -> AgentKey {
        var parts = chord.split(separator: "+", omittingEmptySubsequences: false).map(String.init)
        // A trailing "+" is the plus key itself, as in "cmd++".
        if chord == "+" {
            parts = ["+"]
        } else if chord.hasSuffix("++") {
            parts = Array(parts.dropLast(2)) + ["+"]
        }
        var name = parts.removeLast()
        var modifiers: Modifiers = []
        // Menu-style chords glue their symbols on: "⌘⇧K".
        while name.count > 1, let symbol = name.first, let modifier = modifierNames[String(symbol)] {
            modifiers.insert(modifier)
            name.removeFirst()
        }
        for part in parts {
            guard let modifier = modifierNames[part.lowercased()] else {
                throw ParseError.unknownModifier(part)
            }
            modifiers.insert(modifier)
        }
        if let named = namedKeys[name.lowercased()] {
            return AgentKey(
                keyCode: named.code, characters: named.characters,
                charactersIgnoringModifiers: named.characters,
                modifiers: modifiers.union(named.implied))
        }
        guard name.count == 1, let character = name.first, let typed = typing(character) else {
            throw ParseError.unknownKey(name)
        }
        return AgentKey(
            keyCode: typed.keyCode, characters: typed.characters,
            charactersIgnoringModifiers: typed.charactersIgnoringModifiers,
            modifiers: modifiers.union(typed.modifiers))
    }

    /// The press that types `character`; a character off the ANSI layout carries key code 0.
    static func typing(_ character: Character) -> AgentKey? {
        let text = String(character)
        if let code = ansiCodes[character] {
            return AgentKey(
                keyCode: code, characters: text, charactersIgnoringModifiers: text, modifiers: [])
        }
        if let base = shiftedBase[character] ?? character.lowercased().first,
            base != character, let code = ansiCodes[base]
        {
            return AgentKey(
                keyCode: code, characters: text, charactersIgnoringModifiers: String(base),
                modifiers: .shift)
        }
        if character == " " {
            return AgentKey(keyCode: 49, characters: " ", charactersIgnoringModifiers: " ", modifiers: [])
        }
        guard !character.isNewline else { return try? parse("return") }
        return AgentKey(keyCode: 0, characters: text, charactersIgnoringModifiers: text, modifiers: [])
    }

    private static let modifierNames: [String: Modifiers] = [
        "cmd": .command, "command": .command, "⌘": .command,
        "shift": .shift, "⇧": .shift,
        "opt": .option, "option": .option, "alt": .option, "⌥": .option,
        "ctrl": .control, "control": .control, "⌃": .control,
        "fn": .function,
    ]

    private struct Named {
        let code: UInt16
        let characters: String
        var implied: Modifiers = []
    }

    private static let arrow: Modifiers = [.function, .numericPad]

    private static let namedKeys: [String: Named] = [
        "return": Named(code: 36, characters: "\r"),
        "enter": Named(code: 36, characters: "\r"),
        "tab": Named(code: 48, characters: "\t"),
        "space": Named(code: 49, characters: " "),
        "delete": Named(code: 51, characters: "\u{7F}"),
        "backspace": Named(code: 51, characters: "\u{7F}"),
        "escape": Named(code: 53, characters: "\u{1B}"),
        "esc": Named(code: 53, characters: "\u{1B}"),
        "forwarddelete": Named(code: 117, characters: "\u{F728}", implied: .function),
        "home": Named(code: 115, characters: "\u{F729}", implied: .function),
        "end": Named(code: 119, characters: "\u{F72B}", implied: .function),
        "pageup": Named(code: 116, characters: "\u{F72C}", implied: .function),
        "pagedown": Named(code: 121, characters: "\u{F72D}", implied: .function),
        "left": Named(code: 123, characters: "\u{F702}", implied: arrow),
        "right": Named(code: 124, characters: "\u{F703}", implied: arrow),
        "down": Named(code: 125, characters: "\u{F701}", implied: arrow),
        "up": Named(code: 126, characters: "\u{F700}", implied: arrow),
    ]

    private static let ansiCodes: [Character: UInt16] = [
        "a": 0, "s": 1, "d": 2, "f": 3, "h": 4, "g": 5, "z": 6, "x": 7, "c": 8, "v": 9,
        "b": 11, "q": 12, "w": 13, "e": 14, "r": 15, "y": 16, "t": 17, "1": 18, "2": 19,
        "3": 20, "4": 21, "6": 22, "5": 23, "=": 24, "9": 25, "7": 26, "-": 27, "8": 28,
        "0": 29, "]": 30, "o": 31, "u": 32, "[": 33, "i": 34, "p": 35, "l": 37, "j": 38,
        "'": 39, "k": 40, ";": 41, "\\": 42, ",": 43, "/": 44, "n": 45, "m": 46, ".": 47,
        "`": 50,
    ]

    private static let shiftedBase: [Character: Character] = [
        "!": "1", "@": "2", "#": "3", "$": "4", "%": "5", "^": "6", "&": "7", "*": "8",
        "(": "9", ")": "0", "_": "-", "+": "=", "{": "[", "}": "]", "|": "\\", ":": ";",
        "\"": "'", "<": ",", ">": ".", "?": "/", "~": "`",
    ]
}
