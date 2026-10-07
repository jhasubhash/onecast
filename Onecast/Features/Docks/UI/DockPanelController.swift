import AppKit

/// Owns every custom dock's window: one `DockSurface` per visible dock, the monitors that
/// auto-hide needs, and the popups the docks open. The coordinator hands it the configuration
/// on every change, and it reconciles what is on screen to match.
@MainActor
final class DockPanelController {
    unowned let core: AppCore
    let actions: DockItemActions
    let floating: DockFloatingController

    private var surfaces: [UUID: DockSurface] = [:]
    private var runningMonitor: DockRunningAppsMonitor?
    private var trashMonitor: DockTrashMonitor?
    private var screenObserver: NotificationToken?
    private var pointerMonitors: [Any] = []
    private var yieldTask: Task<Void, Never>?
    private var lastProbe: ContinuousClock.Instant?

    /// How close to its edge the pointer must come before the macOS Dock is looked for.
    private static let probeDistance: CGFloat = 160
    private static let probeInterval = Duration.milliseconds(60)
    private static let yieldPoll = Duration.milliseconds(120)

    init(core: AppCore) {
        self.core = core
        actions = DockItemActions(core: core)
        floating = DockFloatingController(core: core)
    }

    /// Created with the first dock and dropped with the last, so the feature costs nothing off.
    var running: DockRunningAppsMonitor {
        if let runningMonitor { return runningMonitor }
        let monitor = DockRunningAppsMonitor()
        runningMonitor = monitor
        return monitor
    }

    var trash: DockTrashMonitor {
        if let trashMonitor { return trashMonitor }
        let monitor = DockTrashMonitor()
        trashMonitor = monitor
        return monitor
    }

    // MARK: - Contract

    /// Creates, updates and closes panels until one stands for each visible dock.
    func reconcile(_ docks: [CustomDock], enabled: Bool) {
        guard enabled else {
            closeAll()
            return
        }
        arm()
        let visible = docks.filter(\.isVisible)
        let wanted = Set(visible.map(\.id))
        for (id, surface) in Array(surfaces) where !wanted.contains(id) {
            surface.close()
            surfaces[id] = nil
        }
        for dock in visible {
            if let surface = surfaces[dock.id] {
                surface.update(dock)
            } else {
                surfaces[dock.id] = DockSurface(dock: dock, controller: self)
            }
        }
        refreshPointerMonitors()
    }

    func closeAll() {
        floating.close()
        floating.label.hideAll()
        for surface in surfaces.values { surface.close() }
        surfaces.removeAll()
        disarmPointerMonitors()
        yieldTask?.cancel()
        yieldTask = nil
        screenObserver = nil
        runningMonitor = nil
        trashMonitor = nil
    }

    /// The shown frame of every dock that takes space, in global screen coordinates.
    var reservedFrames: [(displayKey: String?, edge: DockEdge, frame: CGRect)] {
        surfaces.values.compactMap { surface in
            surface.reservedFrame.map { (surface.displayKey, surface.model.edge, $0) }
        }
    }

    // MARK: - Screens

    /// The display a dock is saved against, or the menu-bar display when it is gone.
    func screen(forKey key: String?) -> NSScreen? {
        if let key, let match = NSScreen.screens.first(where: { $0.displayKey == key }) {
            return match
        }
        return NSScreen.primary
    }

    func isFullScreen(on screenFrame: CGRect) -> Bool {
        DockScreenProbe.hasFullScreenWindow(on: screenFrame)
    }

    private func arm() {
        if screenObserver == nil {
            let center = NotificationCenter.default
            let token = center.addObserver(
                forName: NSApplication.didChangeScreenParametersNotification, object: nil,
                queue: .main
            ) { [weak self] _ in
                Task { @MainActor in self?.screensChanged() }
            }
            screenObserver = NotificationToken(token, center: center)
        }
        core.dockCoordinator.widgets.onClosePopover = { [weak self] instanceID in
            guard let self, floating.isOpen(.widget(itemID: instanceID)) else { return }
            floating.close()
        }
    }

    private func screensChanged() {
        floating.close()
        for surface in surfaces.values { surface.place() }
    }

    // MARK: - Pointer

    private var needsPointerMonitors: Bool {
        surfaces.values.contains {
            $0.model.dock.appearance.autoHides || $0.canYieldToMacOSDock
        }
    }

    private func refreshPointerMonitors() {
        if needsPointerMonitors {
            armPointerMonitors()
        } else {
            disarmPointerMonitors()
        }
    }

    /// Only armed while some dock hides, so a plain dock never listens to the pointer globally.
    private func armPointerMonitors() {
        guard pointerMonitors.isEmpty else { return }
        let moves: NSEvent.EventTypeMask = [.mouseMoved, .leftMouseDragged]
        if let local = NSEvent.addLocalMonitorForEvents(
            matching: moves,
            handler: { [weak self] event in
                self?.pointerMoved()
                return event
            })
        {
            pointerMonitors.append(local)
        }
        if let global = NSEvent.addGlobalMonitorForEvents(
            matching: moves, handler: { [weak self] _ in self?.pointerMoved() })
        {
            pointerMonitors.append(global)
        }
    }

    private func disarmPointerMonitors() {
        for monitor in pointerMonitors { NSEvent.removeMonitor(monitor) }
        pointerMonitors = []
    }

    private func pointerMoved() {
        let point = NSEvent.mouseLocation
        for surface in surfaces.values { surface.monitoredPointerMoved(to: point) }
        probeMacOSDock(near: point)
    }

    // MARK: - macOS Dock

    private func isNearEdge(_ point: CGPoint, of surface: DockSurface) -> Bool {
        let frame = surface.screenFrame
        guard frame.contains(point) else { return false }
        switch surface.model.edge {
        case .bottom: return point.y - frame.minY <= Self.probeDistance
        case .left: return point.x - frame.minX <= Self.probeDistance
        case .right: return frame.maxX - point.x <= Self.probeDistance
        }
    }

    /// Looks for the macOS Dock's window only while the pointer is near its edge, and keeps
    /// looking, briefly, until it has gone again.
    private func probeMacOSDock(near point: CGPoint) {
        let candidates = surfaces.values.filter(\.canYieldToMacOSDock)
        guard !candidates.isEmpty else { return }
        let nativeEdge = core.dockCoordinator.nativeDock.macOSDockEdge
        let now = ContinuousClock.now
        if let lastProbe, now - lastProbe < Self.probeInterval { return }
        lastProbe = now
        for surface in candidates {
            // A Dock that always shows already holds its edge, and the dock sits beside it.
            guard surface.model.edge == nativeEdge, !surface.reservesEdge else {
                surface.setYielding(false)
                continue
            }
            guard surface.isYielding || isNearEdge(point, of: surface) else { continue }
            surface.setYielding(
                DockScreenProbe.macOSDockIsRevealed(edge: nativeEdge, on: surface.screenFrame))
        }
        pollWhileYielding()
    }

    private func pollWhileYielding() {
        guard yieldTask == nil, surfaces.values.contains(where: \.isYielding) else { return }
        yieldTask = Task { [weak self] in
            while !Task.isCancelled {
                try? await Task.sleep(for: Self.yieldPoll)
                guard let self, !Task.isCancelled else { return }
                let yielding = surfaces.values.filter(\.isYielding)
                guard !yielding.isEmpty else {
                    yieldTask = nil
                    return
                }
                let edge = core.dockCoordinator.nativeDock.macOSDockEdge
                for surface in yielding {
                    surface.setYielding(
                        DockScreenProbe.macOSDockIsRevealed(edge: edge, on: surface.screenFrame))
                }
            }
        }
    }
}
