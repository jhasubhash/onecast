import Foundation

/// A chart's time span: what the popover's picker offers and the query Yahoo is asked for it.
enum StockRange: String, CaseIterable, Sendable, Identifiable {
    case day = "1D"
    case fiveDays = "5D"
    case month = "1M"
    case sixMonths = "6M"
    case year = "1Y"

    var id: String { rawValue }
    var title: String { rawValue }

    var rangeParameter: String {
        switch self {
        case .day: "1d"
        case .fiveDays: "5d"
        case .month: "1mo"
        case .sixMonths: "6mo"
        case .year: "1y"
        }
    }

    /// Yahoo keeps intraday bars for 60 days, so only the short ranges use them.
    var intervalParameter: String {
        switch self {
        case .day: "5m"
        case .fiveDays: "1h"
        case .month, .sixMonths, .year: "1d"
        }
    }

    /// Only a single day has an x-axis worth fixing to the trading session.
    var spansTradingDay: Bool { self == .day }
}
