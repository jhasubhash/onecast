import Foundation

/// Yahoo's answer shapes; every field is optional, since it nulls whatever an instrument lacks.
enum StockWire {
    /// A value that decodes to nil instead of failing, for a field whose shape Yahoo has changed.
    struct Lossy<Value: Decodable>: Decodable {
        let value: Value?

        init(from decoder: any Decoder) throws {
            value = try? Value(from: decoder)
        }
    }

    struct Failure: Decodable {
        let code: String?
        let description: String?
    }

    /// Any answer's error slot, whichever endpoint it came from.
    struct ErrorEnvelope: Decodable {
        struct Slot: Decodable { let error: Failure? }
        let chart: Slot?
        let finance: Slot?
        let quoteResponse: Slot?

        var failure: Failure? { chart?.error ?? finance?.error ?? quoteResponse?.error }
    }

    struct Period: Decodable {
        let start: Double?
        let end: Double?
    }

    struct SessionPeriods: Decodable {
        let pre: Period?
        let regular: Period?
        let post: Period?
    }

    struct ChartEnvelope: Decodable {
        struct Body: Decodable {
            let result: [ChartResult]?
            let error: Failure?
        }
        let chart: Body?
    }

    struct ChartResult: Decodable {
        struct Indicators: Decodable {
            struct Bars: Decodable {
                let open: [Double?]?
                let close: [Double?]?
            }
            let quote: [Bars]?
        }

        let meta: Meta
        let timestamp: [Double?]?
        let indicators: Indicators?
    }

    struct Meta: Decodable {
        let currency: String?
        let longName: String?
        let shortName: String?
        let exchangeTimezoneName: String?
        let priceHint: Double?
        let regularMarketPrice: Double?
        let regularMarketChangePercent: Double?
        let regularMarketDayHigh: Double?
        let regularMarketDayLow: Double?
        let regularMarketVolume: Double?
        let fulldayPrice: Double?
        let fulldayChange: Double?
        let fulldayChangePercent: Double?
        let fiftyTwoWeekHigh: Double?
        let fiftyTwoWeekLow: Double?
        let previousClose: Double?
        let chartPreviousClose: Double?
        let currentTradingPeriod: Lossy<SessionPeriods>?
        /// One inner array per bar day in the range.
        let tradingPeriods: Lossy<[[Period]]>?
    }

    struct QuoteEnvelope: Decodable {
        struct Body: Decodable {
            let result: [Lossy<QuoteRow>]?
            let error: Failure?
        }
        let quoteResponse: Body?
    }

    struct QuoteRow: Decodable {
        let symbol: String?
        let longName: String?
        let shortName: String?
        let currency: String?
        let marketState: String?
        let exchangeTimezoneName: String?
        let priceHint: Double?
        let regularMarketPrice: Double?
        let regularMarketChange: Double?
        let regularMarketChangePercent: Double?
        let regularMarketPreviousClose: Double?
        let regularMarketOpen: Double?
        let regularMarketDayHigh: Double?
        let regularMarketDayLow: Double?
        let regularMarketVolume: Double?
        let fiftyTwoWeekHigh: Double?
        let fiftyTwoWeekLow: Double?
    }
}
