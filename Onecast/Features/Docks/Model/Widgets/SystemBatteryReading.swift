import Foundation

/// The battery's state as the power-source API reports it, ready to show.
struct SystemBatteryReading: Sendable, Equatable {
    enum Status: Sendable, Equatable {
        case discharging, charging, charged
        /// On the adapter but not taking a charge, as Optimized Charging holds a full-enough pack.
        case pluggedIn
    }

    /// The numbers one `IOPSGetPowerSourceDescription` dictionary carries.
    struct Raw: Sendable, Equatable {
        let currentCapacity: Int
        let maximumCapacity: Int
        let isCharging: Bool
        let isCharged: Bool
        let onAdapter: Bool
        /// Minutes; negative while the system is still calculating.
        let minutesToEmpty: Int?
        let minutesToFull: Int?
    }

    let percent: Int
    let status: Status
    /// Minutes to empty while discharging, to full while charging; nil while unknown.
    let minutesRemaining: Int?

    /// Nil for a source that reports no capacity, which no battery does.
    init?(_ raw: Raw) {
        guard raw.maximumCapacity > 0 else { return nil }
        let fraction = Double(raw.currentCapacity) / Double(raw.maximumCapacity)
        percent = SystemFormat.percentValue(fraction)
        if raw.isCharged {
            status = .charged
        } else if raw.isCharging {
            status = .charging
        } else {
            status = raw.onAdapter ? .pluggedIn : .discharging
        }
        switch status {
        case .discharging: minutesRemaining = raw.minutesToEmpty.flatMap { $0 >= 0 ? $0 : nil }
        case .charging: minutesRemaining = raw.minutesToFull.flatMap { $0 >= 0 ? $0 : nil }
        case .charged, .pluggedIn: minutesRemaining = nil
        }
    }

    var isLow: Bool { status == .discharging && percent <= 20 }

    var isOnAdapter: Bool { status != .discharging }

    var statusTitle: String {
        switch status {
        case .discharging: "On battery"
        case .charging: "Charging"
        case .charged: "Fully charged"
        case .pluggedIn: "Plugged in, not charging"
        }
    }

    /// The same state in a word or two, for a tile with little room.
    var tileTitle: String {
        switch status {
        case .discharging: "On battery"
        case .charging: "Charging"
        case .charged: "Charged"
        case .pluggedIn: "Plugged in"
        }
    }

    /// The estimate as "2:15", or nil while it is unknown.
    var estimateText: String? {
        minutesRemaining.map { SystemFormat.hoursAndMinutes(minutes: $0) }
    }

    /// "2:15 remaining", "0:40 until full", or nil when there is nothing sensible to say.
    var timeText: String? {
        switch status {
        case .discharging: estimateText.map { "\($0) remaining" }
        case .charging: estimateText.map { "\($0) until full" }
        case .charged, .pluggedIn: nil
        }
    }

    /// The SF Symbol for the charge, with a bolt while a charger is feeding it.
    var symbol: String {
        let level =
            switch percent {
            case ..<13: "0"
            case ..<38: "25"
            case ..<63: "50"
            case ..<88: "75"
            default: "100"
            }
        return status == .charging ? "battery.\(level)percent.bolt" : "battery.\(level)percent"
    }
}
