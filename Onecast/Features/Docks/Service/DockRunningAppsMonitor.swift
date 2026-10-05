import AppKit

/// The apps a dock lists as running: regular apps in launch order, live from `NSWorkspace`.
@MainActor
@Observable
final class DockRunningAppsMonitor {
    private(set) var apps: [DockRunningApp] = []
    @ObservationIgnored private var observers: [NotificationToken] = []

    init() {
        refresh()
        let center = NSWorkspace.shared.notificationCenter
        for name in [
            NSWorkspace.didLaunchApplicationNotification,
            NSWorkspace.didTerminateApplicationNotification,
            NSWorkspace.didActivateApplicationNotification,
            NSWorkspace.didHideApplicationNotification,
            NSWorkspace.didUnhideApplicationNotification,
        ] {
            let token = center.addObserver(forName: name, object: nil, queue: .main) { [weak self] _ in
                Task { @MainActor in self?.refresh() }
            }
            observers.append(NotificationToken(token, center: center))
        }
    }

    /// Helpers and agents fire these too, so republish only on a real change.
    private func refresh() {
        let ownProcessID = ProcessInfo.processInfo.processIdentifier
        let next = NSWorkspace.shared.runningApplications
            .filter {
                $0.activationPolicy == .regular && !$0.isTerminated
                    && $0.processIdentifier != ownProcessID && $0.bundleURL != nil
            }
            .sorted { Self.launchedBefore($0, $1) }
            .map(Self.dockApp)
        guard next != apps else { return }
        apps = next
    }

    private static func launchedBefore(_ lhs: NSRunningApplication, _ rhs: NSRunningApplication)
        -> Bool
    {
        let left = lhs.launchDate ?? .distantFuture
        let right = rhs.launchDate ?? .distantFuture
        if left != right { return left < right }
        return lhs.processIdentifier < rhs.processIdentifier
    }

    private static func dockApp(_ app: NSRunningApplication) -> DockRunningApp {
        let path = app.bundleURL?.path ?? ""
        return DockRunningApp(
            bundleID: app.bundleIdentifier, path: path,
            name: app.localizedName ?? URL(fileURLWithPath: path).deletingPathExtension().lastPathComponent,
            processID: app.processIdentifier, isActive: app.isActive, isHidden: app.isHidden)
    }
}
