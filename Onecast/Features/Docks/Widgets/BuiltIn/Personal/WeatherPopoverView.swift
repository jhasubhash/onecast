import OnecastPluginKit
import SwiftUI

/// The popover a tile click opens: the full reading, the hours ahead, and the way out of an error.
struct WeatherPopoverView: View {
    let model: WeatherModel
    let context: DockWidgetContext

    var body: some View {
        let settings = model.settings(for: context)
        TimelineView(.periodic(from: .now, by: Self.tick)) { timeline in
            VStack(alignment: .leading, spacing: Theme.Spacing.xl) {
                if let failure = model.failure {
                    WeatherPopoverFailure(
                        failure: failure, isRefreshing: model.isRefreshing, context: context,
                        retry: model.retry)
                }
                if let snapshot = model.snapshot {
                    WeatherPopoverSummary(snapshot: snapshot, unit: settings.unit)
                    WeatherPopoverHours(snapshot: snapshot, unit: settings.unit, now: timeline.date)
                    Text(updated(snapshot, now: timeline.date))
                        .font(Theme.Typography.keyCap)
                        .foregroundStyle(Theme.Colors.textTertiary)
                } else if model.failure == nil {
                    loading
                }
            }
            .padding(PersonalPopover.padding)
        }
        .frame(width: PersonalPopover.width)
    }

    private var loading: some View {
        HStack(spacing: Theme.Spacing.md) {
            ProgressView().controlSize(.small)
            Text("Loading weather…")
                .font(Theme.Typography.rowTrailing)
                .foregroundStyle(Theme.Colors.textSecondary)
        }
    }

    private func updated(_ snapshot: WeatherModel.Snapshot, now: Date) -> String {
        model.isRefreshing
            ? "Updating…" : PersonalWeatherFormat.updated(snapshot.fetchedAt, now: now)
    }

    private static let tick: TimeInterval = 30
}
