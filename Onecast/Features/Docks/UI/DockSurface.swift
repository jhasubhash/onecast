import AppKit
import SwiftUI

/// One dock on screen: its window, its model, and everything the pointer does to it — hover and
/// magnification, auto-hide, menus, popouts, scrolling and drag and drop.
@MainActor
final class DockSurface {
    let model: DockSurfaceModel
    let panel: DockPanel
    private let container: DockContainerView
    private unowned let controller: DockPanelController
    private var core: AppCore { controller.core }
    private var floating: DockFloatingController { controller.floating }

    /// The dock's shown frame at rest, in screen coordinates; what window management reserves.
    private(set) var pill: CGRect = .zero
    private var visibleFrame: CGRect = .zero
    /// Room kept around the plate for the lens: kept always, so hovering never resizes the window.
    private var overscan = (along: CGFloat(0), cross: CGFloat(0))
    private var isOverDock = false
    private var isSettledTucked = false
    private var isRevealed = false
    private(set) var isYielding = false
    private var isDragging = false
    private var reorderedLocally = false
    private var isClosed = false
    private var alignmentOverride: Double?
    private var handleGrab: CGFloat = 0
    private var menuSession: DockMenuSession?
    private var labelSlotID: String?
    private var scrollGesture = ScrollGesture()
    private var lastStepTime: TimeInterval = 0
    /// Where the driver is easing the lens and the pointer, once per display frame.
    private var lensTarget: Double = 0
    private var pointerTarget: CGFloat?
    private lazy var lensDriver = DockLensDriver(view: container) { [weak self] seconds in
        self?.advanceLens(by: seconds) ?? false
    }

    private var hideTask: Task<Void, Never>?
    private var settleTask: Task<Void, Never>?
    private var dwellTask: Task<Void, Never>?
    private var labelTask: Task<Void, Never>?

    /// Window padding around the plate that the plate's shadow falls into.
    private static let pad: CGFloat = 16
    /// The most the lens can add to the whole dock, in multiples of the extra size.
    private static let totalGrowth: CGFloat = 2.5
    /// How quickly the lens zooms in and out: about 0.13 s to settle.
    private static let lensTimeConstant = 0.045
    /// How quickly the lens catches up with the pointer: close enough to feel attached to it.
    private static let pointerTimeConstant = 0.035
    private static let slideSettle = Duration.milliseconds(340)
    private static let hideDelay = Duration.milliseconds(600)
    private static let labelDelay = Duration.milliseconds(350)
    private static let edgeDwell = Duration.milliseconds(350)
    private static let stepThreshold: CGFloat = 24
    private static let axisLockDistance: CGFloat = 6
    private static let stepDebounce: TimeInterval = 0.3
    private static let escapeKeyCode: CGKeyCode = 0x35

    private struct ScrollGesture {
        enum Lock { case undecided, along, across }
        var lock = Lock.undecided
        var along: CGFloat = 0
        var across: CGFloat = 0
        var stepped = false
    }

    init(dock: CustomDock, controller: DockPanelController) {
        self.controller = controller
        let core = controller.core
        model = DockSurfaceModel(
            dock: dock, metrics: core.settings.interfaceSize.metrics, core: core,
            actions: controller.actions, running: controller.running, trash: controller.trash)
        panel = DockPanel(layer: dock.appearance.layer)
        let hosting = NSHostingView(rootView: DockRoot(model: model, core: core))
        hosting.sizingOptions = []
        container = DockContainerView(hosting: hosting)
        panel.contentView = container
        container.surface = self
        model.onWidgetTap = { [weak self] id in self?.widgetTapped(id) }
        model.onActivate = { [weak self] id in self?.click(slotID: id) }
        isSettledTucked = dock.appearance.autoHides
        place()
        observeContent()
    }

    var dockID: UUID { model.dockID }
    private var edge: DockEdge { model.edge }

    /// Docks that take space from other windows: shown, floating, and not tucking away.
    var reservedFrame: CGRect? {
        let dock = model.dock
        guard dock.isVisible, !dock.appearance.autoHides, dock.appearance.layer == .floating else {
            return nil
        }
        return pill
    }

    var displayKey: String? {
        controller.screen(forKey: model.dock.placement.displayKey)?.displayKey
    }

    // MARK: - Configuration

    func update(_ dock: CustomDock) {
        let layerChanged = dock.appearance.layer != model.dock.appearance.layer
        model.update(dock: dock, metrics: core.settings.interfaceSize.metrics)
        if layerChanged { panel.apply(layer: dock.appearance.layer) }
        if !dock.appearance.autoHides { isRevealed = false }
        if let open = model.openSlotID, !model.slots.contains(where: { $0.id == open }) {
            floating.close()
        }
        model.scroll = model.clampedScroll(model.scroll)
        place()
    }

    func close() {
        isClosed = true
        for task in [hideTask, settleTask, dwellTask, labelTask] { task?.cancel() }
        lensDriver.stop()
        if model.openSlotID != nil || floating.isOpen(.menu(dockID: dockID)) { floating.close() }
        floating.label.hide()
        container.surface = nil
        panel.orderOut(nil)
        panel.contentView = nil
        panel.close()
    }

    /// Re-reads everything that sizes the dock; called whenever its slots or the interface change.
    func place() {
        guard !isClosed, let screen = controller.screen(forKey: model.dock.placement.displayKey)
        else { return }
        let dock = model.dock
        model.setMetrics(core.settings.interfaceSize.metrics)
        visibleFrame = screen.visibleFrame
        let tile = model.tileSize
        let room = edge.isVertical ? visibleFrame.height : visibleFrame.width
        let spare = max(room - min(model.restLength, room), 0)
        let configured = model.metrics.scaled(CGFloat(dock.appearance.magnifiedSize))
        let magnified =
            dock.appearance.magnifies
            ? max(tile, min(configured, tile + spare / Self.totalGrowth)) : tile
        model.setRoom(availableLength: room, magnifiedSize: magnified)
        let previous = pill
        pill = DockGeometry.frame(
            length: model.viewport, thickness: model.thickness, edge: edge,
            alignment: alignmentOverride ?? dock.placement.alignment, screen: visibleFrame,
            available: visibleFrame)
        overscan = lensRoom(magnified: magnified)
        model.setPlateGrowth(overscan.along * 2)
        syncPresentation()
        // A dock that grows is given its new room at once and trimmed once the tiles have moved.
        if pill != previous, panel.isVisible, !isSettledTucked, alignmentOverride == nil,
            let target = targetFrame()
        {
            panel.setFrame(panel.frame.union(target), display: true)
            settleTask?.cancel()
            settleTask = Task { [weak self] in
                try? await Task.sleep(for: Self.slideSettle)
                guard !Task.isCancelled else { return }
                self?.applyFrame()
            }
        } else {
            applyFrame()
        }
    }

    /// Slots or Interface Size changing re-places the dock; re-armed on every change.
    private func observeContent() {
        withObservationTracking {
            _ = model.restLength
            _ = core.settings.interfaceSize
        } onChange: { [weak self] in
            Task { @MainActor in
                guard let self, !self.isClosed else { return }
                self.observeContent()
                self.place()
            }
        }
    }

    // MARK: - Frames

    /// The lens's worst-case growth past either end and out from the edge, swept along the strip.
    private func lensRoom(magnified: CGFloat) -> (along: CGFloat, cross: CGFloat) {
        let tile = model.tileSize
        guard magnified > tile else { return (0, 0) }
        let slots = model.stripSlots(model.slots)
        let length = model.restLength
        var along: CGFloat = 0
        for pointer in stride(from: 0, through: length, by: max(tile / 4, 1)) {
            let layout = DockStripLayout.make(
                slots: slots, tileSize: tile, magnifiedSize: magnified, pointer: pointer, lens: 1)
            along = max(along, -layout.plateStart, layout.plateEnd - length)
        }
        return (along, magnified - tile)
    }

    private func expand(_ rect: CGRect, along: CGFloat, cross: CGFloat, edgeSide: CGFloat)
        -> CGRect
    {
        switch edge {
        case .bottom:
            return CGRect(
                x: rect.minX - along, y: rect.minY - edgeSide, width: rect.width + 2 * along,
                height: rect.height + edgeSide + cross)
        case .left:
            return CGRect(
                x: rect.minX - edgeSide, y: rect.minY - along, width: rect.width + edgeSide + cross,
                height: rect.height + 2 * along)
        case .right:
            return CGRect(
                x: rect.minX - cross, y: rect.minY - along, width: rect.width + edgeSide + cross,
                height: rect.height + 2 * along)
        }
    }

    /// The window: the plate and its shadow's room, grown by the lens while the pointer is on it,
    /// or just the handle's strip once the dock has slid away.
    private func targetFrame() -> CGRect? {
        if isSettledTucked {
            let handle = model.tuckedVisible
            guard handle > 0 else { return nil }
            switch edge {
            case .bottom:
                return CGRect(x: pill.minX, y: visibleFrame.minY, width: pill.width, height: handle)
            case .left:
                return CGRect(x: visibleFrame.minX, y: pill.minY, width: handle, height: pill.height)
            case .right:
                return CGRect(
                    x: visibleFrame.maxX - handle, y: pill.minY, width: handle, height: pill.height)
            }
        }
        let extra = model.isMagnifying ? overscan : (along: 0, cross: 0)
        return expand(
            pill, along: Self.pad + extra.along, cross: Self.pad + extra.cross,
            edgeSide: DockGeometry.edgeMargin)
    }

    private func applyFrame() {
        guard !isClosed else { return }
        guard let frame = targetFrame() else {
            panel.orderOut(nil)
            return
        }
        if panel.frame != frame { panel.setFrame(frame, display: true) }
        if !panel.isVisible { panel.orderFrontRegardless() }
    }

    // MARK: - Auto-hide

    private var wantsTucked: Bool {
        (model.dock.appearance.autoHides && !isRevealed) || isYielding
    }

    private var handleVisible: CGFloat {
        !isYielding && model.dock.appearance.showsHandleWhenHidden
            ? DockGeometry.handleThickness : 0
    }

    /// Slides the plate in or out inside its window, then fits the window to what is left.
    private func syncPresentation() {
        if wantsTucked {
            guard !model.isTucked || model.tuckedVisible != handleVisible else { return }
            isOverDock = false
            floating.label.hide()
            settleLens(at: 0)
            model.setTucked(true, visible: handleVisible)
            guard panel.isVisible else {
                isSettledTucked = true
                return
            }
            settleTask?.cancel()
            settleTask = Task { [weak self] in
                try? await Task.sleep(for: Self.slideSettle)
                guard !Task.isCancelled, let self else { return }
                isSettledTucked = true
                applyFrame()
            }
        } else {
            settleTask?.cancel()
            isSettledTucked = false
            guard model.isTucked else { return }
            applyFrame()
            model.setTucked(false, visible: model.tuckedVisible)
        }
    }

    private var revealZone: CGRect {
        DockGeometry.revealZone(shown: pill, edge: edge, screen: visibleFrame)
    }

    /// Fed every pointer move by the controller's monitors, whether or not it is over the dock.
    func monitoredPointerMoved(to point: CGPoint) {
        guard model.dock.appearance.autoHides, !isYielding, !isClosed else { return }
        if !isRevealed {
            if revealZone.contains(point) {
                requestReveal()
            } else {
                dwellTask?.cancel()
                dwellTask = nil
            }
        } else if !containsPointer(point), !holdsOpen {
            scheduleHide()
        }
    }

    /// In a full-screen space the edge is where other apps' toolbars and hot zones live, so the
    /// pointer has to rest there a moment before the dock answers.
    private func requestReveal() {
        guard dwellTask == nil else { return }
        guard controller.isFullScreen(on: screenFrame) else {
            reveal()
            return
        }
        dwellTask = Task { [weak self] in
            try? await Task.sleep(for: Self.edgeDwell)
            guard let self else { return }
            dwellTask = nil
            guard !Task.isCancelled, revealZone.contains(NSEvent.mouseLocation) else { return }
            reveal()
        }
    }

    private func reveal() {
        hideTask?.cancel()
        guard !isRevealed else { return }
        isRevealed = true
        syncPresentation()
    }

    private func scheduleHide() {
        guard model.dock.appearance.autoHides, isRevealed else { return }
        hideTask?.cancel()
        hideTask = Task { [weak self] in
            try? await Task.sleep(for: Self.hideDelay)
            guard !Task.isCancelled, let self else { return }
            guard !holdsOpen, !containsPointer(NSEvent.mouseLocation) else { return }
            isRevealed = false
            syncPresentation()
        }
    }

    /// A menu, popout or drag keeps a dock up even with the pointer elsewhere.
    private var holdsOpen: Bool {
        model.openSlotID != nil || floating.isOpen(.menu(dockID: dockID)) || isDragging
    }

    private func containsPointer(_ point: CGPoint) -> Bool {
        panel.frame.insetBy(dx: -2, dy: -2).contains(point)
    }

    /// The macOS Dock appearing on this edge slides the dock out of its way.
    func setYielding(_ yielding: Bool) {
        guard yielding != isYielding, !isClosed else { return }
        isYielding = yielding
        syncPresentation()
    }

    /// Whether the macOS Dock could appear over this dock: same edge, and not already reserved.
    var canYieldToMacOSDock: Bool {
        model.dock.appearance.hidesWhenMacOSDockAppears && !isClosed
    }

    var screenFrame: CGRect {
        controller.screen(forKey: model.dock.placement.displayKey)?.frame ?? visibleFrame
    }

    var reservesEdge: Bool {
        guard let screen = controller.screen(forKey: model.dock.placement.displayKey) else {
            return false
        }
        let frame = screen.frame
        let visible = screen.visibleFrame
        switch edge {
        case .bottom: return visible.minY - frame.minY > 1
        case .left: return visible.minX - frame.minX > 1
        case .right: return frame.maxX - visible.maxX > 1
        }
    }

    // MARK: - Geometry

    private func currentLayout(_ slots: [DockSlot]) -> DockStripLayout {
        model.layout(lens: model.lens, slots: slots)
    }

    /// A screen point as distances along the dock and from its edge-side rim.
    private func stripPoint(_ point: CGPoint) -> (along: CGFloat, fromEdge: CGFloat) {
        switch edge {
        case .bottom: (point.x - pill.minX, point.y - pill.minY)
        case .left: (pill.maxY - point.y, point.x - pill.minX)
        case .right: (pill.maxY - point.y, pill.maxX - point.x)
        }
    }

    private func screenRect(of frame: CGRect) -> CGRect {
        CGRect(
            x: pill.minX + frame.minX, y: pill.maxY - frame.maxY, width: frame.width,
            height: frame.height)
    }

    private func screenRect(ofSlot index: Int, in layout: DockStripLayout) -> CGRect {
        screenRect(of: model.frame(of: layout.tiles[index]))
    }

    /// The tile under the point, the handle included: it is the strip's last tile.
    private func rawHitIndex(atScreen point: CGPoint, layout: DockStripLayout) -> Int? {
        let strip = stripPoint(point)
        // The gap between the plate and the screen edge belongs to the dock, so a click there lands.
        let gap = DockGeometry.edgeMargin
        let fromEdge = strip.fromEdge < 0 && strip.fromEdge >= -gap ? 0 : strip.fromEdge
        return layout.tileIndex(along: strip.along, fromEdge: fromEdge)
    }

    private func hitIndex(atScreen point: CGPoint, layout: DockStripLayout) -> Int? {
        guard let index = rawHitIndex(atScreen: point, layout: layout),
            index < layout.tiles.count - 1
        else { return nil }
        return index
    }

    /// Over the strip as it is drawn now, so a magnified tile's top and the gaps between counts.
    private func isOverPlate(_ point: CGPoint, layout: DockStripLayout) -> Bool {
        let strip = stripPoint(point)
        return strip.along >= layout.plateStart && strip.along <= layout.plateEnd
            && strip.fromEdge >= -DockGeometry.edgeMargin && strip.fromEdge <= layout.depth
    }

    private func slot(id: String) -> (index: Int, slot: DockSlot)? {
        model.slots.enumerated().first { $0.element.id == id }.map { ($0.offset, $0.element) }
    }

    // MARK: - Moving the dock

    func isOverHandle(atScreen point: CGPoint) -> Bool {
        let layout = currentLayout(model.slots)
        return rawHitIndex(atScreen: point, layout: layout) == layout.tiles.count - 1
    }

    /// A point as its distance along the room the dock lives in, from the room's start.
    private func roomAlong(_ point: CGPoint) -> CGFloat {
        edge.isVertical ? visibleFrame.maxY - point.y : point.x - visibleFrame.minX
    }

    func beginHandleDrag(atScreen point: CGPoint) {
        hideLabel()
        floating.close()
        isDragging = true
        let centre = edge.isVertical ? visibleFrame.maxY - pill.midY : pill.midX - visibleFrame.minX
        handleGrab = roomAlong(point) - centre
    }

    /// The handle follows the pointer along the edge; the dock is saved once, on release.
    func dragHandle(toScreen point: CGPoint) {
        let room = edge.isVertical ? visibleFrame.height : visibleFrame.width
        guard room > 0 else { return }
        alignmentOverride = min(max(Double((roomAlong(point) - handleGrab) / room), 0), 1)
        place()
    }

    func endHandleDrag() {
        isDragging = false
        if let alignment = alignmentOverride {
            core.dockCoordinator.updatePlacement(dockID: dockID) { $0.alignment = alignment }
        }
        alignmentOverride = nil
        place()
        scheduleHide()
    }

    // MARK: - Pointer

    func pointerEntered(atScreen point: CGPoint) {
        hideTask?.cancel()
        if model.isTucked, model.dock.appearance.autoHides, !isYielding { reveal() }
        pointerMoved(toScreen: point)
    }

    func pointerMoved(toScreen point: CGPoint) {
        guard !model.isTucked, !isClosed else { return }
        hideTask?.cancel()
        let slots = model.slots
        let layout = currentLayout(slots)
        let hit = hitIndex(atScreen: point, layout: layout)
        guard hit != nil || isOverPlate(point, layout: layout) else {
            disengage()
            return
        }
        engage(at: stripPoint(point).along)
        updateLabel(hit: hit, slots: slots)
    }

    func pointerExited() {
        disengage()
    }

    // MARK: - Lens motion

    private var reducesMotion: Bool { NSWorkspace.shared.accessibilityDisplayShouldReduceMotion }

    /// Mouse events arrive unevenly, and in pairs, so the lens eases toward each one at the
    /// display's pace rather than jumping to it or stacking animations on one another.
    private func engage(at along: CGFloat) {
        guard isOverDock else {
            isOverDock = true
            // Seeded at once, so the lens never sweeps in from where the last hover ended.
            pointerTarget = along
            if model.pointer != along { model.pointer = along }
            moveLens(to: model.isMagnifying ? 1 : 0)
            return
        }
        guard along != pointerTarget else { return }
        pointerTarget = along
        if reducesMotion { model.pointer = along } else { lensDriver.start() }
    }

    private func moveLens(to target: Double) {
        lensTarget = target
        if reducesMotion {
            if model.lens != target { model.lens = target }
        } else {
            lensDriver.start()
        }
    }

    /// For a dock sliding away: the lens drops to rest at once, with nothing left to ease.
    private func settleLens(at target: Double) {
        lensDriver.stop()
        lensTarget = target
        if model.lens != target { model.lens = target }
    }

    /// One display frame; returns whether anything is still moving.
    private func advanceLens(by seconds: Double) -> Bool {
        var moving = false
        let lens = DockLensDriver.approach(
            model.lens, to: lensTarget, seconds: seconds, timeConstant: Self.lensTimeConstant)
        if abs(lens - lensTarget) < 0.001 {
            if model.lens != lensTarget { model.lens = lensTarget }
        } else {
            model.lens = lens
            moving = true
        }
        if let target = pointerTarget, let pointer = model.pointer {
            let next = CGFloat(
                DockLensDriver.approach(
                    Double(pointer), to: Double(target), seconds: seconds,
                    timeConstant: Self.pointerTimeConstant))
            if abs(next - target) < 0.05 {
                if model.pointer != target { model.pointer = target }
            } else {
                model.pointer = next
                moving = true
            }
        }
        return moving
    }

    private func disengage() {
        guard isOverDock else { return }
        isOverDock = false
        moveLens(to: 0)
        hideLabel()
        scheduleHide()
    }

    // MARK: - Label

    private func updateLabel(hit: Int?, slots: [DockSlot]) {
        guard let hit, !floating.isOpen, let name = model.name(of: slots[hit]) else {
            hideLabel()
            return
        }
        let id = slots[hit].id
        let anchor = screenRect(ofSlot: hit, in: currentLayout(slots))
        if labelSlotID == id, labelTask == nil {
            floating.label.show(name, anchor: anchor, edge: edge)
            return
        }
        guard labelSlotID != id else { return }
        hideLabel()
        labelSlotID = id
        labelTask = Task { [weak self] in
            try? await Task.sleep(for: Self.labelDelay)
            guard !Task.isCancelled, let self else { return }
            labelTask = nil
            guard labelSlotID == id, isOverDock, !floating.isOpen,
                let current = slot(id: id)
            else { return }
            let layout = currentLayout(model.slots)
            floating.label.show(
                name, anchor: screenRect(ofSlot: current.index, in: layout), edge: edge)
        }
    }

    private func hideLabel() {
        labelTask?.cancel()
        labelTask = nil
        labelSlotID = nil
        floating.label.hide()
    }

    // MARK: - Clicks

    /// A widget tile takes its clicks itself, so the container replays a press that was no drag.
    func isWidget(slotID: String) -> Bool {
        guard let found = slot(id: slotID), case .pinned(let item, _) = found.slot,
            case .widget = item.kind
        else { return false }
        return true
    }

    func slotID(atScreen point: CGPoint) -> String? {
        let slots = model.slots
        guard let index = hitIndex(atScreen: point, layout: currentLayout(slots)) else {
            return nil
        }
        if case .divider = slots[index] { return nil }
        return slots[index].id
    }

    func opensOnHold(slotID: String) -> Bool {
        guard let found = slot(id: slotID), case .pinned(let item, _) = found.slot,
            case .folder = item.kind
        else { return false }
        return true
    }

    func click(slotID: String) {
        guard let found = slot(id: slotID) else { return }
        hideLabel()
        let options = model.dock.content
        switch found.slot {
        case .pinned(let item, let running):
            switch item.kind {
            case .app(let reference):
                model.actions.activate(
                    reference, running: running,
                    minimizesWhenFocused: options.clickFocusedAppMinimizes)
            case .folder(let folder):
                toggleFolder(found, item: item, folder: folder)
            case .file(let path):
                model.actions.open(path: path)
            case .link(let link):
                model.actions.open(link: link)
            case .shortcut(let name):
                model.actions.runShortcut(named: name)
            case .spacer, .widget:
                break
            }
        case .running(let app):
            model.actions.activate(app, minimizesWhenFocused: options.clickFocusedAppMinimizes)
        case .minimized(let window):
            model.windows.restore(window.token)
        case .trash:
            model.actions.openTrash()
        case .divider:
            break
        }
    }

    func hold(slotID: String) {
        guard let found = slot(id: slotID), case .pinned(let item, _) = found.slot,
            case .folder(let folder) = item.kind
        else { return }
        hideLabel()
        presentFolder(found, item: item, folder: folder)
    }

    // MARK: - Popups

    private func popupAnchor(index: Int) -> CGRect {
        screenRect(ofSlot: index, in: currentLayout(model.slots))
    }

    private func toggleFolder(
        _ found: (index: Int, slot: DockSlot), item: DockItem, folder: DockFolderReference
    ) {
        let owner = DockFloatingController.Owner.folder(itemID: item.id)
        if floating.isOpen(owner) {
            floating.close()
            return
        }
        guard !floating.wasJustDismissed(owner) else { return }
        presentFolder(found, item: item, folder: folder)
    }

    private func presentFolder(
        _ found: (index: Int, slot: DockSlot), item: DockItem, folder: DockFolderReference
    ) {
        let title = folder.customName ?? FileManager.default.displayName(atPath: folder.path)
        let popout = DockFolderPopoutModel(path: folder.path, title: title)
        let view = DockFolderPopoutView(
            model: popout,
            open: { [weak self] entry in
                self?.floating.close()
                AppLauncher.open(URL(fileURLWithPath: entry.path))
            },
            openInFinder: { [weak self] in
                self?.floating.close()
                self?.model.actions.open(path: folder.path)
            })
        floating.present(
            AnyView(view), owner: .folder(itemID: item.id), anchor: popupAnchor(index: found.index),
            edge: edge, onDismiss: { [weak self] in self?.popupDismissed() })
        model.openSlotID = found.slot.id
        Task { await popout.load() }
    }

    private func widgetTapped(_ itemID: UUID) {
        guard let found = model.slots.enumerated().first(where: {
            if case .pinned(let item, _) = $0.element { item.id == itemID } else { false }
        }), case .pinned(let item, _) = found.element, case .widget(let reference) = item.kind
        else { return }
        let owner = DockFloatingController.Owner.widget(itemID: itemID)
        if floating.isOpen(owner) {
            floating.close()
            return
        }
        guard !floating.wasJustDismissed(owner),
            let content = core.dockCoordinator.widgets.popoverView(
                instanceID: itemID, reference: reference, edge: edge, tileLength: model.tileSize)
        else { return }
        hideLabel()
        floating.present(
            AnyView(DockWidgetPopoverView(content: content)), owner: owner,
            anchor: popupAnchor(index: found.offset), edge: edge,
            onDismiss: { [weak self] in self?.popupDismissed() })
        model.openSlotID = found.element.id
    }

    private func popupDismissed() {
        model.openSlotID = nil
        menuSession = nil
        if !containsPointer(NSEvent.mouseLocation) { scheduleHide() }
    }

    // MARK: - Menus

    func showMenu(atScreen point: CGPoint) {
        hideLabel()
        let slots = model.slots
        let layout = currentLayout(slots)
        let context = DockMenus.Context(
            core: core, dock: model.dock, actions: model.actions)
        if let index = hitIndex(atScreen: point, layout: layout) {
            let content = DockMenus.tile(slots[index], context: context)
            if !content.items.isEmpty {
                presentMenu(content, anchor: screenRect(ofSlot: index, in: layout))
                return
            }
        }
        let strip = stripPoint(point)
        let band = plateBand(along: strip.along)
        presentMenu(
            DockMenus.background(context, showLayouts: { [weak self] in self?.showLayoutsPage() }),
            anchor: band)
    }

    /// A hairline across the plate at `along`, which a menu on the dock itself hangs from.
    private func plateBand(along: CGFloat) -> CGRect {
        let frame =
            edge.isVertical
            ? CGRect(x: 0, y: along - 0.5, width: model.thickness, height: 1)
            : CGRect(x: along - 0.5, y: 0, width: 1, height: model.thickness)
        return screenRect(of: frame)
    }

    private func presentMenu(_ content: PopoverMenuContent, anchor: CGRect) {
        let session = DockMenuSession(content: content, floating: floating)
        floating.present(
            session.view, owner: .menu(dockID: dockID), anchor: anchor, edge: edge,
            keys: { [weak session] event in session?.handleKey(event) },
            onDismiss: { [weak self] in self?.popupDismissed() })
        menuSession = session
    }

    private func showLayoutsPage() {
        guard let session = menuSession else { return }
        let context = DockMenus.Context(core: core, dock: model.dock, actions: model.actions)
        let back = { [weak self, weak session] in
            guard let self, let session else { return }
            session.show(
                DockMenus.background(
                    context, showLayouts: { [weak self] in self?.showLayoutsPage() }))
        }
        session.show(DockMenus.layouts(context, back: back))
    }

    // MARK: - Scrolling and layout switching

    func scroll(_ event: NSEvent) {
        let vertical = edge.isVertical
        let deltaX = event.scrollingDeltaX
        let deltaY = event.scrollingDeltaY
        let isGesture = !event.phase.isEmpty || !event.momentumPhase.isEmpty
        if event.phase.contains(.began) || event.phase.contains(.mayBegin) {
            scrollGesture = ScrollGesture()
        }
        if event.modifierFlags.contains(.command) {
            commandScroll(event, delta: abs(deltaY) >= abs(deltaX) ? deltaY : deltaX, isGesture: isGesture)
            return
        }
        let along = vertical ? deltaY : (deltaX != 0 ? deltaX : deltaY)
        // A wheel scrolls the strip and never switches layouts; only a trackpad swipe does.
        guard isGesture else {
            scrollStrip(by: along)
            return
        }
        let across = vertical ? deltaX : deltaY
        if !event.momentumPhase.isEmpty {
            if scrollGesture.lock == .along { scrollStrip(by: along) }
            return
        }
        scrollGesture.along += along
        scrollGesture.across += across
        if scrollGesture.lock == .undecided,
            max(abs(scrollGesture.along), abs(scrollGesture.across)) > Self.axisLockDistance
        {
            scrollGesture.lock = abs(scrollGesture.along) >= abs(scrollGesture.across) ? .along : .across
        }
        switch scrollGesture.lock {
        case .along:
            scrollStrip(by: along)
        case .across:
            if !scrollGesture.stepped, abs(scrollGesture.across) > Self.stepThreshold {
                scrollGesture.stepped = true
                step(scrollGesture.across)
            }
        case .undecided:
            break
        }
    }

    /// ⌘-scroll steps layouts from any device: once per gesture, or once per wheel burst.
    private func commandScroll(_ event: NSEvent, delta: CGFloat, isGesture: Bool) {
        guard delta != 0 else { return }
        if isGesture {
            guard !scrollGesture.stepped else { return }
            scrollGesture.across += delta
            guard abs(scrollGesture.across) > Self.stepThreshold else { return }
            scrollGesture.stepped = true
            step(scrollGesture.across)
        } else if event.timestamp - lastStepTime > Self.stepDebounce {
            step(delta)
        }
        if !isGesture { lastStepTime = event.timestamp }
    }

    /// Scrolling down or toward the far edge moves on; the other way moves back.
    private func step(_ delta: CGFloat) {
        core.dockCoordinator.stepLayout(dockID: dockID, by: delta < 0 ? 1 : -1)
    }

    private func scrollStrip(by delta: CGFloat) {
        guard model.scrolls, !floating.isOpen, delta != 0 else { return }
        model.scroll = model.clampedScroll(model.scroll - delta)
    }

    // MARK: - Dragging out

    func dragPayload(slotID: String) -> DockDragPayload? {
        guard let found = slot(id: slotID), case .pinned(let item, _) = found.slot else {
            return nil
        }
        let layout = currentLayout(model.slots)
        let tile = layout.tiles[found.index]
        let rect = screenRect(ofSlot: found.index, in: layout)
        let snapshot: NSImage? = if case .widget = item.kind { image(ofScreenRect: rect) } else { nil }
        return DockDragPayload(
            source: DockDragItem(
                dockID: dockID, layoutID: model.dock.activeLayoutID, item: item),
            image: snapshot ?? model.actions.dragImage(for: item, side: tile.cross),
            screenRect: rect)
    }

    /// The tile as drawn, so a widget drags as itself rather than as a generic glyph.
    private func image(ofScreenRect rect: CGRect) -> NSImage? {
        guard let view = panel.contentView else { return nil }
        let local = view.convert(panel.convertFromScreen(rect), from: nil)
        guard !local.isEmpty, let bitmap = view.bitmapImageRepForCachingDisplay(in: local) else {
            return nil
        }
        view.cacheDisplay(in: local, to: bitmap)
        let image = NSImage(size: local.size)
        image.addRepresentation(bitmap)
        return image
    }

    func dragBegan(slotID: String) {
        isDragging = true
        reorderedLocally = false
        hideLabel()
        floating.close()
        model.draggingSlotID = slotID
    }

    /// Dropped on a dock it moved already; dragged off, a tile is removed but a widget returns.
    func dragEnded(_ payload: DockDragPayload?, atScreen point: CGPoint, operation: NSDragOperation) {
        isDragging = false
        model.draggingSlotID = nil
        model.drop = nil
        defer { reorderedLocally = false }
        guard let payload, !reorderedLocally, !operation.contains(.move) else { return }
        let source = payload.source
        let cancelled = CGEventSource.keyState(.combinedSessionState, key: Self.escapeKeyCode)
        let layout = currentLayout(model.slots)
        let isWidget = if case .widget = source.item.kind { true } else { false }
        guard !cancelled, !isWidget, !isOverPlate(point, layout: layout) else {
            scheduleHide()
            return
        }
        core.dockCoordinator.removeItem(id: source.item.id, dockID: source.dockID, layoutID: source.layoutID)
        DockPoof.show(image: payload.image, atScreen: point)
    }

    // MARK: - Dropping in

    private enum DropTarget {
        case reorder(from: Int, to: Int)
        case move(DockDragItem, to: Int)
        case add([URL], at: Int)
        case openWith([URL], DockAppReference, slotID: String)
        case receive([URL], any DockFileReceiving, slotID: String)
        case trash([URL])

        var feedback: DockSurfaceModel.DropFeedback {
            switch self {
            case .reorder(_, let index), .move(_, let index), .add(_, let index):
                .insert(index: index)
            case .openWith(_, _, let id), .receive(_, _, let id): .openWith(slotID: id)
            case .trash: .trash
            }
        }

        var preferredOperations: [NSDragOperation] {
            switch self {
            case .reorder, .move: [.move]
            case .add, .openWith, .receive: [.copy, .generic, .link]
            case .trash: [.move, .generic, .copy]
            }
        }
    }

    private func dropTarget(for pasteboard: NSPasteboard, atScreen point: CGPoint) -> DropTarget? {
        guard !model.isTucked, !isClosed else { return nil }
        let slots = model.slots
        let layout = currentLayout(slots)
        let strip = stripPoint(point)
        let items = model.dock.activeLayout.items
        let index = layout.insertionIndex(along: strip.along, count: items.count)

        if let data = pasteboard.data(forType: .dockItem),
            let drag = try? JSONDecoder().decode(DockDragItem.self, from: data)
        {
            if drag.dockID == dockID, let from = items.firstIndex(where: { $0.id == drag.item.id }) {
                return .reorder(from: from, to: index)
            }
            return .move(drag, to: index)
        }
        let urls = (pasteboard.readObjects(forClasses: [NSURL.self], options: nil) as? [URL]) ?? []
        guard !urls.isEmpty else { return nil }
        let files = urls.allSatisfy(\.isFileURL)
        if let hit = hitIndex(atScreen: point, layout: layout) {
            let target = slots[hit]
            if case .trash = target, files { return .trash(urls) }
            if files, !urls.contains(where: { $0.pathExtension == "app" }),
                let reference = appReference(of: target)
            {
                return .openWith(urls, reference, slotID: target.id)
            }
            if case .pinned(let item, _) = target, case .widget(let widget) = item.kind,
                let receiver = core.dockCoordinator.widgets.widget(
                    for: item.id, widgetID: widget.widgetID) as? any DockFileReceiving
            {
                return .receive(urls, receiver, slotID: target.id)
            }
        }
        return .add(urls, at: index)
    }

    private func appReference(of slot: DockSlot) -> DockAppReference? {
        switch slot {
        case .pinned(let item, _):
            if case .app(let reference) = item.kind { reference } else { nil }
        case .running(let app):
            DockAppReference(bundleID: app.bundleID, path: app.path)
        default:
            nil
        }
    }

    func dragUpdated(_ sender: any NSDraggingInfo) -> NSDragOperation {
        let point = panel.convertPoint(toScreen: sender.draggingLocation)
        guard let target = dropTarget(for: sender.draggingPasteboard, atScreen: point) else {
            model.drop = nil
            return []
        }
        model.drop = target.feedback
        let allowed = sender.draggingSourceOperationMask
        return target.preferredOperations.first { allowed.contains($0) } ?? []
    }

    func dragExited() {
        model.drop = nil
    }

    func dragPerformed(_ sender: any NSDraggingInfo) -> Bool {
        defer { model.drop = nil }
        let point = panel.convertPoint(toScreen: sender.draggingLocation)
        guard let target = dropTarget(for: sender.draggingPasteboard, atScreen: point) else {
            return false
        }
        let dock = model.dock
        let coordinator = core.dockCoordinator
        switch target {
        case .reorder(let from, let to):
            coordinator.moveItem(dockID: dock.id, layoutID: dock.activeLayoutID, from: from, to: to)
            reorderedLocally = true
        case .move(let drag, let to):
            coordinator.transferItem(
                id: drag.item.id, fromDock: drag.dockID, layout: drag.layoutID,
                toDock: dock.id, layout: dock.activeLayoutID, at: to)
        case .add(let urls, let index):
            coordinator.addItems(
                DockCoordinator.items(for: urls), dockID: dock.id, layoutID: dock.activeLayoutID,
                at: index)
        case .openWith(let urls, let reference, _):
            model.actions.open(urls, with: reference)
        case .receive(let urls, let receiver, _):
            return receiver.receive(urls)
        case .trash(let urls):
            model.actions.moveToTrash(urls)
        }
        return true
    }
}

/// The dock's SwiftUI tree with the environment its tiles and widgets read.
private struct DockRoot: View {
    let model: DockSurfaceModel
    let core: AppCore

    var body: some View {
        DockView(model: model).dockEnvironment(core)
    }
}
