import Foundation

/// Where an exchange is in its day. Only the regular session counts as open for refreshing.
enum StockMarketState: Sendable, Equatable {
    case pre, regular, post, closed

    var isOpen: Bool { self == .regular }

    var title: String {
        switch self {
        case .pre: "Pre-market"
        case .regular: "Market open"
        case .post: "After hours"
        case .closed: "Market closed"
        }
    }

    /// Yahoo's `marketState`; its PREPRE and POSTPOST are the dead hours outside extended trading.
    init(yahoo: String?) {
        switch yahoo?.uppercased() {
        case "REGULAR": self = .regular
        case "PRE": self = .pre
        case "POST": self = .post
        default: self = .closed
        }
    }

    /// A chart's `currentTradingPeriod` read against the clock, for answers that carry no state.
    init(
        at now: Date, pre: StockTradingWindow?, regular: StockTradingWindow?,
        post: StockTradingWindow?
    ) {
        if regular?.contains(now) == true {
            self = .regular
        } else if pre?.contains(now) == true {
            self = .pre
        } else if post?.contains(now) == true {
            self = .post
        } else {
            self = .closed
        }
    }
}
