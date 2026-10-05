import Foundation

/// Posts and withdraws the notifications the time widgets raise, through Onecast's own presenter.
@MainActor
enum TimeNotificationService {
    private static let dwell: TimeInterval = 8

    /// A passing notice, such as a Pomodoro phase ending; it dismisses itself after a few seconds.
    static func announce(title: String, body: String, tint: NotificationTint) {
        let spec = NotificationSpec(
            id: UUID(), title: title, body: body, style: .banner, corner: .topTrailing,
            dwell: dwell, actions: [], tint: tint)
        AppCore.shared.notificationPresenter.post(spec, playsSound: false)
    }

    /// A notice that stays until it is answered; `onAction` gets the tapped action's id.
    static func ask(
        title: String, body: String, tint: NotificationTint, actions: [NotificationAction],
        onAction: @escaping (String) -> Void
    ) -> UUID {
        let spec = NotificationSpec(
            id: UUID(), title: title, body: body, style: .card, corner: .topTrailing,
            dwell: nil, actions: actions, tint: tint)
        return AppCore.shared.notificationPresenter.post(spec, playsSound: false, onAction: onAction)
    }

    static func withdraw(_ id: UUID) {
        AppCore.shared.notificationPresenter.dismiss(id)
    }
}
