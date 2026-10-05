import OnecastPluginKit
import SwiftUI

/// Codex's rate-limit windows and the tokens Claude Code and Codex have used, from local logs.
final class AIUsageDockWidget: OnecastDockWidget {
    static let metadata = DockWidgetMetadata(
        name: "AI Usage", subtitle: "Codex limits and Claude Code and Codex token activity",
        icon: AIUsageGlyph.widget, category: "Personal", sizes: [.compact, .wide, .expanded])

    static let preferences: [PluginPreference] = [
        PluginPreference(
            name: PersonalAIUsageSettings.Name.content, title: "Shows",
            description:
                "AI Limits are Codex's rate-limit windows. AI Activity adds up tokens from your local logs.",
            kind: .dropdown,
            options: PersonalAIUsageContent.allCases.map {
                PluginPreference.Option(title: $0.title, value: $0.rawValue)
            },
            defaultValue: .string(PersonalAIUsageContent.standard.rawValue)),
        PluginPreference(
            name: PersonalAIUsageSettings.Name.range, title: "Activity range",
            description: "The days AI Activity adds up. A day runs midnight to midnight, your time.",
            kind: .dropdown,
            options: PersonalAIUsageRange.allCases.map {
                PluginPreference.Option(title: $0.title, value: $0.rawValue)
            },
            defaultValue: .string(PersonalAIUsageRange.standard.rawValue)),
        PluginPreference(
            name: PersonalAIUsageSettings.Name.display, title: "Display", kind: .dropdown,
            options: PersonalAIUsageDisplay.allCases.map {
                PluginPreference.Option(title: $0.title, value: $0.rawValue)
            },
            defaultValue: .string(PersonalAIUsageDisplay.standard.rawValue)),
        PluginPreference(
            name: PersonalAIUsageSettings.Name.measure, title: "Limits show",
            description: "Whether a limit reads as the share left or the share used.",
            kind: .dropdown,
            options: PersonalAIUsageMeasure.allCases.map {
                PluginPreference.Option(title: $0.title, value: $0.rawValue)
            },
            defaultValue: .string(PersonalAIUsageMeasure.standard.rawValue)),
    ]

    private let model = AIUsageModel()

    required init() {}

    func tile(context: DockWidgetContext) -> AnyView {
        AnyView(AIUsageTile(model: model, context: context))
    }

    func popover(context: DockWidgetContext) -> AnyView? {
        AnyView(AIUsagePopover(model: model, context: context))
    }

    func didRemove() {
        model.didRemove()
    }
}
