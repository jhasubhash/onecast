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

// MARK: - HUD

/// The mark leading a HUD message pill: the same three Onecast's own confirmations use.
@frozen public enum OnecastHUDTone: String, Sendable, CaseIterable {
    case info, success, failure
}

/// Long-running work reported in the HUD pill. It stays up, without a dwell, until the next
/// progress, a message, or `hideHUDProgress()` replaces it.
public struct OnecastHUDProgress: Sendable, Equatable {
    public var message: String
    /// 0...1 draws a filling ring; nil draws the indeterminate spinner.
    public var fraction: Double?

    public init(message: String, fraction: Double? = nil) {
        self.message = message
        self.fraction = fraction
    }
}

// MARK: - Services

/// What Onecast offers a plugin or DockWidget beyond its own views: its notification cards, its HUD
/// pill and its scheduler. A DockWidget reads it from `DockWidgetContext.services`; a plugin is handed it once
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
    public typealias CancelHandler = @MainActor @Sendable () -> Void

    private let post: @MainActor @Sendable (OnecastNotification, ActionHandler?) -> String
    private let withdraw: @MainActor @Sendable (String) -> Void
    private let register: @MainActor @Sendable (OnecastSchedule, @escaping FireHandler) -> Void
    private let cancel: @MainActor @Sendable (String) -> Void
    private let hud: @MainActor @Sendable (String, OnecastHUDTone) -> Void
    private let hudProgress: @MainActor @Sendable (OnecastHUDProgress, CancelHandler?) -> Void
    private let hudHide: @MainActor @Sendable () -> Void

    public init(
        notify: @escaping @MainActor @Sendable (OnecastNotification, ActionHandler?) -> String,
        dismissNotification: @escaping @MainActor @Sendable (String) -> Void,
        schedule: @escaping @MainActor @Sendable (OnecastSchedule, @escaping FireHandler) -> Void,
        unschedule: @escaping @MainActor @Sendable (String) -> Void,
        showHUD: @escaping @MainActor @Sendable (String, OnecastHUDTone) -> Void,
        showHUDProgress: @escaping @MainActor @Sendable (OnecastHUDProgress, CancelHandler?) -> Void,
        hideHUDProgress: @escaping @MainActor @Sendable () -> Void
    ) {
        post = notify
        withdraw = dismissNotification
        register = schedule
        cancel = unschedule
        hud = showHUD
        hudProgress = showHUDProgress
        hudHide = hideHUDProgress
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

    /// Onecast's message pill, the one its own confirmations use; it fades after a few seconds.
    @MainActor
    public func showHUD(_ message: String, tone: OnecastHUDTone = .success) {
        hud(message, tone)
    }

    /// The pill with a spinner or, given a fraction, a filling ring, for background work the user
    /// started and can't otherwise see. Call again to update it. With `onCancel`, clicking the pill
    /// calls it. One pill is shared by the whole app, so another report may replace this one; the
    /// next update brings it back.
    @MainActor
    public func showHUDProgress(_ progress: OnecastHUDProgress, onCancel: CancelHandler? = nil) {
        hudProgress(progress, onCancel)
    }

    @MainActor
    public func hideHUDProgress() {
        hudHide()
    }

    /// Accepts every call and does nothing: for previews and tests.
    public static let inert = OnecastHostServices(
        notify: { _, _ in UUID().uuidString }, dismissNotification: { _ in },
        schedule: { _, _ in }, unschedule: { _ in },
        showHUD: { _, _ in }, showHUDProgress: { _, _ in }, hideHUDProgress: {})
}
