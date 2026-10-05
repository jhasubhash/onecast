import OnecastPluginKit
import SwiftUI

/// The instance's preferences as SwiftUI sees them, so an edit redraws the tile and popover.
@MainActor
struct AIUsageStoredSettings: DynamicProperty {
    @AppStorage private var content: String
    @AppStorage private var range: String
    @AppStorage private var display: String
    @AppStorage private var measure: String

    init(instanceID: String) {
        func key(_ name: String) -> String {
            DockWidgetPreferences.key(instanceID: instanceID, name: name)
        }
        _content = AppStorage(
            wrappedValue: PersonalAIUsageContent.standard.rawValue,
            key(PersonalAIUsageSettings.Name.content))
        _range = AppStorage(
            wrappedValue: PersonalAIUsageRange.standard.rawValue,
            key(PersonalAIUsageSettings.Name.range))
        _display = AppStorage(
            wrappedValue: PersonalAIUsageDisplay.standard.rawValue,
            key(PersonalAIUsageSettings.Name.display))
        _measure = AppStorage(
            wrappedValue: PersonalAIUsageMeasure.standard.rawValue,
            key(PersonalAIUsageSettings.Name.measure))
    }

    var value: PersonalAIUsageSettings {
        PersonalAIUsageSettings(content: content, range: range, display: display, measure: measure)
    }
}

/// The AI Usage tile: Codex's limits or token activity, as numbers, rings or bars.
struct AIUsageTile: View {
    let model: AIUsageModel
    let context: DockWidgetContext
    private let stored: AIUsageStoredSettings

    /// Fine enough that a reset countdown never reads stale, coarse enough to be free.
    private static let refreshSeconds: TimeInterval = 30
    private let calendar = Calendar.autoupdatingCurrent

    init(model: AIUsageModel, context: DockWidgetContext) {
        self.model = model
        self.context = context
        stored = AIUsageStoredSettings(instanceID: context.instanceID)
    }

    var body: some View {
        let metrics = PersonalTileMetrics(context)
        let settings = stored.value
        TimelineView(.periodic(from: .now, by: Self.refreshSeconds)) { timeline in
            let plan = model.plan(settings: settings, now: timeline.date, calendar: calendar)
            PersonalTileCard(metrics) {
                content(plan, settings: settings, metrics: metrics)
            }
            .accessibilityElement(children: .ignore)
            .accessibilityLabel(plan.spoken)
        }
        .task(id: context.instanceID) { await model.run(context) }
    }

    @ViewBuilder
    private func content(
        _ plan: AIUsagePlan, settings: PersonalAIUsageSettings, metrics: PersonalTileMetrics
    ) -> some View {
        if plan.resolution == nil {
            AIUsageEmptyTile(metrics: metrics, isChecking: plan.isChecking)
        } else if metrics.isCompact, let summary = plan.summary {
            AIUsageCellView(cell: summary, display: settings.display, metrics: metrics, isRow: false)
        } else {
            let layout =
                metrics.isVertical
                ? AnyLayout(VStackLayout(spacing: metrics.spacing))
                : AnyLayout(HStackLayout(spacing: metrics.spacing))
            layout {
                ForEach(plan.cells) { cell in
                    AIUsageCellView(
                        cell: cell, display: settings.display, metrics: metrics,
                        isRow: plan.cells.count > 1
                    )
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                }
            }
        }
    }
}

/// What a tile says when nothing has any data: muted, with a hint on anything bigger than compact.
struct AIUsageEmptyTile: View {
    let metrics: PersonalTileMetrics
    let isChecking: Bool

    private static let hint = "Use Codex or Claude Code to see usage here"

    var body: some View {
        VStack(spacing: metrics.spacing) {
            SymbolImage(name: AIUsageGlyph.widget, size: metrics.symbolSize(0.3))
                .foregroundStyle(Theme.Colors.textTertiary)
            Text(isChecking ? "Checking…" : "No AI data")
                .font(metrics.font(.label))
                .foregroundStyle(Theme.Colors.textSecondary)
                .lineLimit(1)
                .minimumScaleFactor(0.5)
            if !metrics.isCompact && !isChecking {
                Text(Self.hint)
                    .font(metrics.font(.caption, weight: .medium))
                    .foregroundStyle(Theme.Colors.textTertiary)
                    .multilineTextAlignment(.center)
                    .lineLimit(metrics.isVertical ? 4 : 2)
                    .minimumScaleFactor(0.5)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}
