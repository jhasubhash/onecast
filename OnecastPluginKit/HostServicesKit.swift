import Foundation

// MARK: - Notifications

/// A notification drawn as Onecast's own floating card, the one its Scheduler posts.
public struct OnecastNotification: Sendable, Equatable {
    public var title: String
    public var body: String
    public var tint: OnecastNotificationTint?
    /// Buttons on the card; tapping one hands its `id` to the poster's `onAction`.
    public var actions: [OnecastNotificationAction]
    /// Seconds before the card dismisses itself; nil keeps it until it is closed or answered.
    public var dwell: TimeInterval?
    public var playsSound: Bool

    public init(
        title: String, body: String = "", tint: OnecastNotificationTint? = nil,
        actions: [OnecastNotificationAction] = [], dwell: TimeInterval? = 8, playsSound: Bool = false
    ) {
        self.title = title
        self.body = body
        self.tint = tint
        self.actions = actions
        self.dwell = dwell
        self.playsSound = playsSound
    }
}

/// The card's accent; a fixed palette, so every one stays legible in both appearances.
@frozen public enum OnecastNotificationTint: String, Sendable, CaseIterable {
    case blue, purple, pink, red, orange, yellow, green, teal, gray
}

public struct OnecastNotificationAction: Sendable, Equatable {
    public var id: String
    public var title: String

    public init(id: String, title: String) {
        self.id = id
        self.title = title
    }
}

// MARK: - Schedules

@frozen public enum OnecastScheduleRule: Sendable, Equatable {
    case once(Date)
    case interval(seconds: TimeInterval)
    case daily(hour: Int, minute: Int)
    /// `weekdays` uses Calendar weekday integers: 1 = Sunday … 7 = Saturday.
    case weekly(weekdays: Set<Int>, hour: Int, minute: Int)
}

/// A schedule a plugin or DockWidget registers. Settings › Scheduler lists it under its owner, where
/// the user can switch it off but not edit it.
public struct OnecastSchedule: Sendable, Equatable {
    /// Unique within its owner; registering the same id again replaces the schedule.
    public var id: String
    /// The row title in Settings › Scheduler.
    public var title: String
    public var rule: OnecastScheduleRule

    public init(id: String, title: String, rule: OnecastScheduleRule) {
        self.id = id
        self.title = title
        self.rule = rule
    }
}

/// One occurrence handed to a schedule's handler.
public struct OnecastScheduleFire: Sendable, Equatable {
    public let scheduleID: String
    /// The occurrence this fire stands for; in the past when `isLate`.
    public let date: Date
    /// Missed while Onecast was quit or the Mac asleep, and fired on return instead.
    public let isLate: Bool

    public init(scheduleID: String, date: Date, isLate: Bool) {
        self.scheduleID = scheduleID
        self.date = date
        self.isLate = isLate
    }
}

// MARK: - Services

/// What Onecast offers a plugin or DockWidget beyond its own views: its notification cards and its
/// scheduler. A DockWidget reads it from `DockWidgetContext.services`; a plugin is handed it once
/// through `OnecastPlugin.bind(services:)`.
///
/// Schedules are code-owned: re-register them every time the owner is created (they are not
/// restored for you), and the handler runs on the main actor at each occurrence. Onecast keeps
/// each schedule's last fire, so an occurrence missed while it was quit or the Mac slept fires
/// once, late, on the next registration or wake. A DockWidget's schedules end with its instance;
/// a plugin's survive a closed palette, and Onecast loads the plugin at launch to re-register them.
public struct OnecastHostServices: Sendable {
    public typealias ActionHandler = @MainActor @Sendable (String) -> Void
    public typealias FireHandler = @MainActor @Sendable (OnecastScheduleFire) -> Void

    private let post: @MainActor @Sendable (OnecastNotification, ActionHandler?) -> String
    private let withdraw: @MainActor @Sendable (String) -> Void
    private let register: @MainActor @Sendable (OnecastSchedule, @escaping FireHandler) -> Void
    private let cancel: @MainActor @Sendable (String) -> Void

    public init(
        notify: @escaping @MainActor @Sendable (OnecastNotification, ActionHandler?) -> String,
        dismissNotification: @escaping @MainActor @Sendable (String) -> Void,
        schedule: @escaping @MainActor @Sendable (OnecastSchedule, @escaping FireHandler) -> Void,
        unschedule: @escaping @MainActor @Sendable (String) -> Void
    ) {
        post = notify
        withdraw = dismissNotification
        register = schedule
        cancel = unschedule
    }

    /// Shows a card now and returns its id. `onAction` gets the tapped button's id; the card stays
    /// up until dismissed, so close it from there when the answer settles it.
    @MainActor @discardableResult
    public func notify(_ notification: OnecastNotification, onAction: ActionHandler? = nil) -> String {
        post(notification, onAction)
    }

    @MainActor
    public func dismissNotification(_ id: String) {
        withdraw(id)
    }

    @MainActor
    public func schedule(_ schedule: OnecastSchedule, fire: @escaping FireHandler) {
        register(schedule, fire)
    }

    @MainActor
    public func unschedule(_ id: String) {
        cancel(id)
    }

    /// Accepts every call and does nothing: for previews and tests.
    public static let inert = OnecastHostServices(
        notify: { _, _ in UUID().uuidString }, dismissNotification: { _ in },
        schedule: { _, _ in }, unschedule: { _ in })
}
