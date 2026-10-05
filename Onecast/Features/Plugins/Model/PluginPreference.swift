import Foundation

/// One entry of a plugin manifest's `preferences`: a setting the plugin reads through
/// `PluginPreferences` and Settings › Plugins edits. A subset of an extension's preference schema.
struct PluginPreference: Codable, Sendable, Hashable {
    enum Kind: String, Codable, Sendable {
        case textfield, checkbox, dropdown, directory
    }

    struct Option: Codable, Sendable, Hashable {
        let title: String
        let value: String
    }

    let name: String
    let title: String
    var description: String?
    var placeholder: String?
    var kind: Kind
    var options: [Option]
    var defaultValue: PluginPreferenceValue?

    init(
        name: String, title: String, description: String? = nil, placeholder: String? = nil,
        kind: Kind = .textfield, options: [Option] = [], defaultValue: PluginPreferenceValue? = nil
    ) {
        self.name = name
        self.title = title
        self.description = description
        self.placeholder = placeholder
        self.kind = kind
        self.options = options
        self.defaultValue = defaultValue
    }

    private enum CodingKeys: String, CodingKey {
        case name, title, description, placeholder, options
        case kind = "type"
        case defaultValue = "default"
    }

    /// A missing or unknown `type` is a text field, so one typo never hides a plugin's settings.
    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        name = try c.decode(String.self, forKey: .name)
        title = try c.decodeIfPresent(String.self, forKey: .title) ?? name
        description = try c.decodeIfPresent(String.self, forKey: .description)
        placeholder = try c.decodeIfPresent(String.self, forKey: .placeholder)
        kind = (try? c.decodeIfPresent(Kind.self, forKey: .kind)) ?? .textfield
        options = try c.decodeIfPresent([Option].self, forKey: .options) ?? []
        defaultValue = try c.decodeIfPresent(PluginPreferenceValue.self, forKey: .defaultValue)
    }

    /// What the host registers as the default, in the type the plugin reads it as.
    var registeredDefault: Any? {
        switch defaultValue {
        case .string(let value)?: kind == .checkbox ? (value == "true") : value
        case .bool(let value)?: kind == .checkbox ? value : String(value)
        case nil: nil
        }
    }
}

/// A manifest default: a checkbox's `true`/`false`, anything else as text (`8799` reads as "8799").
enum PluginPreferenceValue: Codable, Sendable, Hashable {
    case string(String)
    case bool(Bool)

    init(from decoder: Decoder) throws {
        let c = try decoder.singleValueContainer()
        if let flag = try? c.decode(Bool.self) {
            self = .bool(flag)
        } else if let number = try? c.decode(Double.self) {
            self = .string(number.rounded() == number ? String(Int(number)) : String(number))
        } else {
            self = .string(try c.decode(String.self))
        }
    }

    func encode(to encoder: Encoder) throws {
        var c = encoder.singleValueContainer()
        switch self {
        case .string(let value): try c.encode(value)
        case .bool(let value): try c.encode(value)
        }
    }
}
