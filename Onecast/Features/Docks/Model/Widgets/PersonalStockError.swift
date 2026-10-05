import Foundation

/// Everything that can go wrong fetching a quote, each with a sentence a user can act on.
enum StockError: Error, Sendable, Equatable, LocalizedError {
    case noSymbols
    /// Yahoo has no instrument by this symbol.
    case unknownSymbol(String)
    /// Yahoo's own explanation, passed through when it sent one.
    case api(String)
    case rateLimited
    /// The cookie and crumb Yahoo asks of every quote request were refused.
    case unauthorized
    case server(Int)
    case offline
    case timedOut
    case network(String)
    case malformed

    var message: String {
        switch self {
        case .noSymbols: "No symbol set. Add one in this widget's settings."
        case .unknownSymbol(let symbol): "Yahoo Finance has no quote for \(symbol)."
        case .api(let description): description
        case .rateLimited: "Yahoo Finance is limiting requests right now. Try again in a minute."
        case .unauthorized: "Yahoo Finance refused the request."
        case .server(let status): "Yahoo Finance is unavailable (HTTP \(status))."
        case .offline: "You're offline."
        case .timedOut: "Yahoo Finance didn't answer in time."
        case .network(let description): description
        case .malformed: "Yahoo Finance sent an answer Onecast couldn't read."
        }
    }

    var errorDescription: String? { message }

    /// A failure that may be the crumb's fault, so the next request should earn a fresh one.
    var invalidatesCrumb: Bool {
        switch self {
        case .unauthorized, .malformed, .api: true
        default: false
        }
    }

    /// Whether asking again soon can help; a wrong symbol stays wrong until the setting changes.
    var isTransient: Bool {
        switch self {
        case .noSymbols, .unknownSymbol, .api: false
        default: true
        }
    }
}
