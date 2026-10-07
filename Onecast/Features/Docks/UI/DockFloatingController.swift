import AppKit
import SwiftUI

extension View {
    /// Reports the size the content wants, so a panel hosting it can follow as it changes.
    fileprivate func reportingSize(_ report: @escaping (CGSize) -> Void) -> some View {
        fixedSize().onGeometryChange(for: CGSize.self) { $0.size } action: { report($0) }
    }
}

/// The one popup a dock has open at a time — its menu, a folder's contents or a widget's popover
/// — and the label that names a hovered tile.
@MainActor
final class DockFloatingController {
    enum Owner: Hashable {
        case menu(dockID: UUID)
        case folder(itemID: UUID)
        case widget(itemID: UUID)
    }

    private unowned let core: AppCore
    private var panel: DockFloatingPanel?
    private(set) var owner: Owner?
    private var placement: (anchor: CGRect, edge: DockEdge)?
    private var onDismiss: (() -> Void)?
    private var monitors: [Any] = []
    private var resignObserver: NotificationToken?
    private var lastDismissal: (owner: Owner, at: ContinuousClock.Instant)?
    let label: DockLabelPresenter

    /// A click that dismisses a popup is followed by the release that would reopen it.
    private static let reopenGrace = Duration.milliseconds(300)

    init(core: AppCore) {
        self.core = core
        label = DockLabelPresenter(core: core)
    }

    var isOpen: Bool { owner != nil }

    func isOpen(_ owner: Owner) -> Bool { self.owner == owner }

    /// Whether `owner` was closed by the press that is now being released over its tile.
    func wasJustDismissed(_ owner: Owner) -> Bool {
        guard let lastDismissal, lastDismissal.owner == owner else { return false }
        return ContinuousClock.now - lastDismissal.at < Self.reopenGrace
    }

    func present(
        _ content: AnyView, owner: Owner, anchor: CGRect, edge: DockEdge,
        keys: ((NSEvent) -> Void)? = nil, onDismiss: @escaping () -> Void
    ) {
        dismiss(animated: false)
        label.hide()
        let panel = DockFloatingPanel()
        let host = NSHostingView(rootView: wrapped(content))
        host.sizingOptions = [.intrinsicContentSize]
        panel.contentView = host
        panel.keyHandler = keys
        panel.onCancel = { [weak self] in self?.close() }
        panel.pointerHandler = { [weak self] event in self?.pointerEvent(event) }
        self.panel = panel
        self.owner = owner
        self.onDismiss = onDismiss
        placement = (anchor, edge)
        resize(to: host.fittingSize)
        if case .menu = owner {
            core.palette.disarmHoverHighlight(pointerAt: NSEvent.mouseLocation)
        }
        installMonitors(for: panel)
        panel.fadeIn(duration: Theme.Duration.enter) { panel.makeKeyAndOrderFront(nil) }
    }

    /// Swaps what the open popup shows, keeping its window: a menu moving to its next page.
    func replace(with content: AnyView) {
        guard let host = panel?.contentView as? NSHostingView<AnyView> else { return }
        host.rootView = wrapped(content)
        resize(to: host.fittingSize)
    }

    func close() {
        dismiss(animated: true)
    }

    private func dismiss(animated: Bool) {
        guard let closing = panel else { return }
        for monitor in monitors { NSEvent.removeMonitor(monitor) }
        monitors = []
        resignObserver = nil
        let callback = onDismiss
        if let owner { lastDismissal = (owner, .now) }
        panel = nil
        owner = nil
        placement = nil
        onDismiss = nil
        closing.keyHandler = nil
        closing.pointerHandler = nil
        closing.onCancel = nil
        if animated {
            closing.fadeOut(duration: Theme.Duration.exit) { closing.close() }
        } else {
            closing.orderOut(nil)
            closing.close()
        }
        callback?()
    }

    private func wrapped(_ content: AnyView) -> AnyView {
        AnyView(
            content.dockEnvironment(core).reportingSize { [weak self] size in
                self?.resize(to: size)
            })
    }

    private func resize(to size: CGSize) {
        guard let panel, let placement, size.width > 0, size.height > 0 else { return }
        let visible = Self.visibleFrame(containing: placement.anchor)
        let spacing = core.settings.interfaceSize.metrics.spacing.md
        let fitted = DockPopupPlacement.fittedSize(size, in: visible, margin: spacing)
        let frame = DockPopupPlacement.frame(
            size: fitted, anchor: placement.anchor, edge: placement.edge, visible: visible,
            gap: spacing, margin: spacing)
        guard panel.frame != frame else { return }
        panel.setFrame(frame, display: true)
        panel.invalidateShadow()
    }

    static func visibleFrame(containing rect: CGRect) -> CGRect {
        let centre = CGPoint(x: rect.midX, y: rect.midY)
        let screen = NSScreen.screens.first { NSMouseInRect(centre, $0.frame, false) }
        return (screen ?? NSScreen.primary)?.visibleFrame ?? .zero
    }

    // MARK: - Dismissal and pointer

    /// Rows light on real pointer movement, never on a scroll under the pointer.
    private func pointerEvent(_ event: NSEvent) {
        switch event.type {
        case .mouseMoved: core.palette.notePointerMoved(to: NSEvent.mouseLocation)
        case .scrollWheel: core.palette.disarmHoverHighlight(pointerAt: NSEvent.mouseLocation)
        default: break
        }
    }

    private func installMonitors(for panel: DockFloatingPanel) {
        let presses: NSEvent.EventTypeMask = [.leftMouseDown, .rightMouseDown, .otherMouseDown]
        // A press in another window of ours, then one in another app: neither reaches the panel.
        if let local = NSEvent.addLocalMonitorForEvents(
            matching: presses,
            handler: { [weak self, weak panel] event in
                if event.window !== panel { self?.close() }
                return event
            })
        {
            monitors.append(local)
        }
        if let global = NSEvent.addGlobalMonitorForEvents(
            matching: presses, handler: { [weak self] _ in self?.close() })
        {
            monitors.append(global)
        }
        let center = NotificationCenter.default
        let token = center.addObserver(
            forName: NSWindow.didResignKeyNotification, object: panel, queue: .main
        ) { [weak self] _ in
            Task { @MainActor in self?.close() }
        }
        resignObserver = NotificationToken(token, center: center)
    }
}

/// A tile's name, shown beside it in a panel of its own.
@MainActor
final class DockLabelPresenter {
    private unowned let core: AppCore
    private var panel: HUDPanel?
    private var host: NSHostingView<AnyView>?
    private var text: String?

    init(core: AppCore) {
        self.core = core
    }

    func show(_ text: String, anchor: CGRect, edge: DockEdge) {
        let metrics = core.settings.interfaceSize.metrics
        let panel = panel ?? makePanel()
        if self.text != text || host == nil {
            let host = NSHostingView(
                rootView: AnyView(DockLabelView(text: text).environment(\.metrics, metrics)))
            host.sizingOptions = [.intrinsicContentSize]
            panel.contentView = host
            self.host = host
            self.text = text
        }
        guard let host else { return }
        let size = host.fittingSize
        let visible = DockFloatingController.visibleFrame(containing: anchor)
        panel.setFrame(
            DockPopupPlacement.frame(
                size: size, anchor: anchor, edge: edge, visible: visible,
                gap: metrics.spacing.sm, margin: metrics.spacing.xs),
            display: true)
        if panel.isVisible {
            panel.cancelFade()
        } else {
            panel.fadeIn(duration: Theme.Duration.tooltip) { panel.orderFrontRegardless() }
        }
    }

    func hide() {
        text = nil
        guard let panel, panel.isVisible else { return }
        panel.fadeOut(duration: Theme.Duration.exit)
    }

    private func makePanel() -> HUDPanel {
        let panel = HUDPanel(acceptsMouseEvents: false)
        // Above a dock at the system Dock's level, and above the HUDs that clear it.
        panel.level = .popUpMenu
        self.panel = panel
        return panel
    }
}
