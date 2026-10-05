import SwiftUI

extension TimelineSchedule where Self == PeriodicTimelineSchedule {
    /// Ticks on whole seconds, so a shown second never trails the wall clock by a fraction.
    static var everySecond: PeriodicTimelineSchedule {
        let wholeSecond = Date().timeIntervalSinceReferenceDate.rounded(.down)
        return .periodic(from: Date(timeIntervalSinceReferenceDate: wholeSecond), by: 1)
    }
}
