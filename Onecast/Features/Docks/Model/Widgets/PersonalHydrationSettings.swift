import Foundation

/// An instance's preferences, clamped so garbage text never reaches the maths.
struct HydrationSettings: Sendable, Equatable {
    enum Unit: Sendable, Equatable {
        case milliliters
        case drinks
    }

    static let defaultReminderMinutes = 60
    static let reminderMinutesRange = 1...1440
    static let defaultDrinkMilliliters = 250
    static let drinkMillilitersRange = 1...5000
    static let defaultGoalMilliliters = 2000
    static let goalMillilitersRange = 100...20000
    static let defaultGoalDrinks = 8
    static let goalDrinksRange = 1...100

    /// Nil when reminders are off.
    let reminderMinutes: Int?
    let savesHistory: Bool
    let tracksAmounts: Bool
    let drinkMilliliters: Int
    let goalMilliliters: Int
    let goalDrinks: Int

    /// Empty or non-positive turns reminders off; text that is not a number keeps the default.
    init(
        reminder: String?, savesHistory: Bool, tracksAmounts: Bool, drinkSize: String?,
        goalMilliliters: String?, goalDrinks: String?
    ) {
        reminderMinutes = Self.reminder(reminder)
        self.savesHistory = savesHistory
        self.tracksAmounts = tracksAmounts
        drinkMilliliters = Self.whole(
            drinkSize, default: Self.defaultDrinkMilliliters, range: Self.drinkMillilitersRange)
        self.goalMilliliters = Self.whole(
            goalMilliliters, default: Self.defaultGoalMilliliters, range: Self.goalMillilitersRange)
        self.goalDrinks = Self.whole(
            goalDrinks, default: Self.defaultGoalDrinks, range: Self.goalDrinksRange)
    }

    /// What an instance reads before any preference is set.
    static let standard = HydrationSettings(
        reminder: String(defaultReminderMinutes), savesHistory: true, tracksAmounts: true,
        drinkSize: nil, goalMilliliters: nil, goalDrinks: nil)

    var unit: Unit { tracksAmounts ? .milliliters : .drinks }

    func progress(for day: HydrationDay) -> HydrationProgress {
        switch unit {
        case .milliliters:
            HydrationProgress(consumed: day.milliliters, goal: goalMilliliters, unit: .milliliters)
        case .drinks:
            HydrationProgress(consumed: day.count, goal: goalDrinks, unit: .drinks)
        }
    }

    private static func reminder(_ raw: String?) -> Int? {
        guard let raw else { return nil }
        guard let minutes = Int(raw.trimmingCharacters(in: .whitespaces)) else {
            return defaultReminderMinutes
        }
        guard minutes > 0 else { return nil }
        return min(minutes, reminderMinutesRange.upperBound)
    }

    private static func whole(_ raw: String?, default fallback: Int, range: ClosedRange<Int>) -> Int {
        guard let raw, let value = Int(raw.trimmingCharacters(in: .whitespaces)) else {
            return fallback
        }
        return min(max(value, range.lowerBound), range.upperBound)
    }
}

/// How far today is toward the goal, in whichever unit the instance counts.
struct HydrationProgress: Sendable, Equatable {
    let consumed: Int
    let goal: Int
    let unit: HydrationSettings.Unit

    var fraction: Double { Double(consumed) / Double(max(goal, 1)) }
    /// What a ring draws: it stops at full.
    var ringFraction: Double { min(fraction, 1) }
    var percent: Int { Int((fraction * 100).rounded()) }
    var isReached: Bool { consumed >= goal }
}
