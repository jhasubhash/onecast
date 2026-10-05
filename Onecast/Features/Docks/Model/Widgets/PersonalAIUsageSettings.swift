import Foundation

/// Which of the two things the widget can show an instance is set to show.
enum PersonalAIUsageContent: String, Sendable, CaseIterable {
    case limits
    case activity

    static let standard = PersonalAIUsageContent.limits

    var title: String {
        switch self {
        case .limits: "AI Limits"
        case .activity: "AI Activity"
        }
    }

    var other: PersonalAIUsageContent { self == .limits ? .activity : .limits }

    /// What shows when the chosen kind has no data. Nil means neither kind has any.
    static func resolve(
        preferred: PersonalAIUsageContent, hasLimits: Bool, hasActivity: Bool
    ) -> PersonalAIUsageResolution? {
        func has(_ content: PersonalAIUsageContent) -> Bool {
            content == .limits ? hasLimits : hasActivity
        }
        if has(preferred) {
            return PersonalAIUsageResolution(content: preferred, isFallback: false)
        }
        if has(preferred.other) {
            return PersonalAIUsageResolution(content: preferred.other, isFallback: true)
        }
        return nil
    }
}

struct PersonalAIUsageResolution: Sendable, Equatable {
    let content: PersonalAIUsageContent
    /// The chosen kind was empty, so the other one stands in and the popover says so.
    let isFallback: Bool
}

enum PersonalAIUsageDisplay: String, Sendable, CaseIterable {
    case numbers
    case rings
    case bars

    static let standard = PersonalAIUsageDisplay.rings

    var title: String {
        switch self {
        case .numbers: "Numbers"
        case .rings: "Rings"
        case .bars: "Bars"
        }
    }
}

/// One instance's preferences, with anything unset or unrecognised read as its default.
struct PersonalAIUsageSettings: Sendable, Equatable {
    enum Name {
        static let content = "content"
        static let range = "range"
        static let display = "display"
        static let measure = "measure"
    }

    var content = PersonalAIUsageContent.standard
    var range = PersonalAIUsageRange.standard
    var display = PersonalAIUsageDisplay.standard
    var measure = PersonalAIUsageMeasure.standard

    init() {}

    init(content: String?, range: String?, display: String?, measure: String?) {
        self.content = content.flatMap(PersonalAIUsageContent.init(rawValue:)) ?? .standard
        self.range = range.flatMap(PersonalAIUsageRange.init(rawValue:)) ?? .standard
        self.display = display.flatMap(PersonalAIUsageDisplay.init(rawValue:)) ?? .standard
        self.measure = measure.flatMap(PersonalAIUsageMeasure.init(rawValue:)) ?? .standard
    }
}
