import OnecastPluginKit
import SwiftUI

/// The Watchlist tile: compact turns through the symbols; wider ones list two or four at once.
struct WatchlistTileView: View {
    let model: WatchlistModel
    let context: DockWidgetContext

    private let locale = Locale.autoupdatingCurrent
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    private static let staleOpacity = 0.5
    private static let turnDuration = 0.3
    private static let dotLength: CGFloat = 0.035

    var body: some View {
        let metrics = PersonalTileMetrics(context)
        PersonalTileCard(metrics) {
            if model.symbols.isEmpty {
                empty(metrics)
            } else if metrics.isCompact {
                rotating(metrics)
            } else {
                list(metrics)
            }
        }
        .opacity(model.isStale ? Self.staleOpacity : 1)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(summary)
        .task(id: context.instanceID) { await model.run(preferences: context.preferences) }
    }

    private func rotating(_ metrics: PersonalTileMetrics) -> some View {
        TimelineView(.periodic(from: Date(timeIntervalSinceReferenceDate: 0), by: StockRotation.period)) {
            timeline in
            let entries = model.entries
            let index = StockRotation.index(at: timeline.date, count: entries.count)
            VStack(spacing: metrics.spacing) {
                if entries.indices.contains(index) {
                    WatchlistTileCell(entry: entries[index], metrics: metrics)
                        .id(entries[index].symbol)
                        .transition(.opacity)
                }
                dots(metrics, count: entries.count, current: index)
            }
            .animation(reduceMotion ? nil : .easeInOut(duration: Self.turnDuration), value: index)
        }
    }

    private func dots(_ metrics: PersonalTileMetrics, count: Int, current: Int) -> some View {
        let length = metrics.tileLength * Self.dotLength
        return HStack(spacing: length) {
            ForEach(0..<count, id: \.self) { index in
                Circle()
                    .fill(index == current ? Theme.Colors.textSecondary : Theme.Colors.textTertiary)
                    .frame(width: length, height: length)
            }
        }
        .opacity(count > 1 ? 1 : 0)
    }

    private func list(_ metrics: PersonalTileMetrics) -> some View {
        let slots = Self.slots(metrics)
        let shown = Array(model.entries.prefix(slots.rows * slots.columns))
        let rows = stride(from: 0, to: shown.count, by: slots.columns).map {
            Array(shown[$0..<min($0 + slots.columns, shown.count)])
        }
        return VStack(spacing: metrics.spacing) {
            ForEach(rows.indices, id: \.self) { row in
                HStack(spacing: metrics.spacing * 2) {
                    ForEach(rows[row]) { entry in
                        WatchlistTileCell(entry: entry, metrics: metrics)
                    }
                }
            }
        }
    }

    /// Two entries wide, four expanded; a horizontal tile, one tile tall, packs them in columns.
    private static func slots(_ metrics: PersonalTileMetrics) -> (rows: Int, columns: Int) {
        let count = metrics.size == .expanded ? 4 : 2
        return metrics.isVertical ? (count, 1) : (2, count / 2)
    }

    private func empty(_ metrics: PersonalTileMetrics) -> some View {
        VStack(spacing: metrics.spacing / 2) {
            Text(StockFormat.placeholder)
                .font(metrics.font(.value))
                .foregroundStyle(Theme.Colors.textTertiary)
            if !metrics.isCompact {
                Text("No symbols")
                    .font(metrics.font(.caption))
                    .foregroundStyle(Theme.Colors.textTertiary)
            }
        }
    }

    private var summary: String {
        guard !model.symbols.isEmpty else { return "Watchlist, no symbols" }
        let lines = model.entries.map { entry in
            entry.quote.map { quote in
                "\(entry.symbol) \(quote.formatted(quote.price, locale: locale)), "
                    + "\(quote.direction.spoken) \(quote.percentText(locale: locale))"
            } ?? "\(entry.symbol), no quote"
        }
        let stale = model.isStale ? ", not up to date" : ""
        return "Watchlist: " + lines.joined(separator: "; ") + stale
    }
}
