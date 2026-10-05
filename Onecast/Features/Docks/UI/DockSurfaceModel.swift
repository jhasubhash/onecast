import AppKit
import SwiftUI

/// What one dock's SwiftUI surface reads: its configuration, what joins it, and the pointer.
@MainActor
@Observable
final class DockSurfaceModel {
    /// What a drag in progress would do on landing: a gap to drop into, or a tile to drop on.
    enum DropFeedback: Equatable {
        case insert(index: Int)
        case openWith(slotID: String)
        case trash
    }

    let dockID: UUID
    private(set) var dock: CustomDock
    private(set) var metrics: InterfaceMetrics
    private unowned let core: AppCore
    let actions: DockItemActions
    let running: DockRunningAppsMonitor
    let trash: DockTrashMonitor

    /// The pointer along the axis in the dock's rest frame; nil when it is not over the dock.
    var pointer: CGFloat?
    /// 0 at rest, 1 under full magnification; animated so the lens eases in and out.
    var lens: Double = 0
    var scroll: CGFloat = 0
    var draggingSlotID: String?
    var drop: DropFeedback?
    /// The tile whose folder popout or widget popover is up.
    var openSlotID: String?
    var isTucked = false
    /// How much of a tucked dock stays on screen: the handle, or nothing.
    private(set) var tuckedVisible: CGFloat = 0
    /// The longest the dock may be along its axis: the room the screen leaves it.
    private(set) var availableLength: CGFloat = .greatestFiniteMagnitude
    /// The magnified tile size the screen has room for; the tile size when there is none.
    private(set) var magnifiedSize: CGFloat
    /// The most the lens ever adds along the axis: the plate's one width while it is hovered.
    private(set) var plateGrowth: CGFloat = 0

    @ObservationIgnored private var names: [String: String?] = [:]
    @ObservationIgnored private var resolved: [UUID: URL?] = [:]
    @ObservationIgnored var onWidgetTap: ((UUID) -> Void)?
    /// What VoiceOver's press does on a tile, since the tile itself carries no gesture.
    @ObservationIgnored var onActivate: ((String) -> Void)?

    init(
        dock: CustomDock, metrics: InterfaceMetrics, core: AppCore, actions: DockItemActions,
        running: DockRunningAppsMonitor, trash: DockTrashMonitor
    ) {
        dockID = dock.id
        self.dock = dock
        self.metrics = metrics
        self.core = core
        self.actions = actions
        self.running = running
        self.trash = trash
        magnifiedSize = metrics.scaled(CGFloat(dock.appearance.tileSize))
    }

    // MARK: - Configuration

    func update(dock: CustomDock, metrics: InterfaceMetrics) {
        self.dock = dock
        self.metrics = metrics
        names.removeAll()
        resolved.removeAll()
    }

    func setMetrics(_ metrics: InterfaceMetrics) {
        if self.metrics != metrics { self.metrics = metrics }
    }

    func setRoom(availableLength: CGFloat, magnifiedSize: CGFloat) {
        if self.availableLength != availableLength { self.availableLength = availableLength }
        if self.magnifiedSize != magnifiedSize { self.magnifiedSize = magnifiedSize }
    }

    func setTucked(_ tucked: Bool, visible: CGFloat) {
        tuckedVisible = visible
        isTucked = tucked
    }

    var edge: DockEdge { dock.placement.edge }
    var windows: DockWindowObserver { core.dockCoordinator.windows }
    var tileSize: CGFloat { metrics.scaled(CGFloat(dock.appearance.tileSize)) }

    var slots: [DockSlot] {
        DockSlots.arrange(
            items: dock.activeLayout.items, running: running.apps, minimized: windows.minimized,
            options: dock.content)
    }

    // MARK: - Geometry

    /// The grabber at the dock's end: a short spacer the plate draws a pill in.
    private static let handleSlot = DockStripLayout.Slot(extent: .spacer(.small), magnifies: false)

    func stripSlots(_ slots: [DockSlot]) -> [DockStripLayout.Slot] {
        slots.map(\.stripSlot) + [Self.handleSlot]
    }

    var restLength: CGFloat {
        DockGeometry.length(of: stripSlots(slots).map(\.extent), tileSize: tileSize)
    }

    var thickness: CGFloat { DockGeometry.thickness(tileSize: tileSize) }
    var inset: CGFloat { tileSize * DockGeometry.insetRatio }
    /// The dock's length on screen: all of its content, or the screen's room if that is less.
    var viewport: CGFloat { min(restLength, availableLength) }
    var scrolls: Bool { restLength > viewport + 0.5 }
    var maxScroll: CGFloat { max(restLength - viewport, 0) }
    var isMagnifying: Bool { dock.appearance.magnifies && !scrolls }

    func clampedScroll(_ value: CGFloat) -> CGFloat { min(max(value, 0), maxScroll) }

    func layout(lens: Double, slots: [DockSlot]) -> DockStripLayout {
        DockStripLayout.make(
            slots: stripSlots(slots), tileSize: tileSize,
            magnifiedSize: isMagnifying ? magnifiedSize : tileSize, pointer: pointer,
            lens: CGFloat(lens), scroll: scrolls ? clampedScroll(scroll) : 0,
            plateGrowth: isMagnifying ? plateGrowth : 0)
    }

    func setPlateGrowth(_ growth: CGFloat) {
        if plateGrowth != growth { plateGrowth = growth }
    }

    /// The dock's rest frame: where the unmagnified plate sits, origin at its top leading corner.
    var restSize: CGSize {
        edge.isVertical ? CGSize(width: thickness, height: viewport) : CGSize(width: viewport, height: thickness)
    }

    /// A tile's frame in the rest frame; a magnified tile grows away from the dock's edge.
    func frame(of tile: DockStripLayout.Tile) -> CGRect {
        switch edge {
        case .bottom:
            return CGRect(
                x: tile.along, y: thickness - inset - tile.cross, width: tile.length,
                height: tile.cross)
        case .left:
            return CGRect(x: inset, y: tile.along, width: tile.cross, height: tile.length)
        case .right:
            return CGRect(
                x: thickness - inset - tile.cross, y: tile.along, width: tile.cross,
                height: tile.length)
        }
    }

    func plateFrame(_ layout: DockStripLayout) -> CGRect {
        let length = layout.plateEnd - layout.plateStart
        return edge.isVertical
            ? CGRect(x: 0, y: layout.plateStart, width: thickness, height: length)
            : CGRect(x: layout.plateStart, y: 0, width: length, height: thickness)
    }

    /// Everything the lens has grown, from the edge-side rim out to the tallest tile.
    func envelopeFrame(_ layout: DockStripLayout) -> CGRect {
        let length = layout.plateEnd - layout.plateStart
        let depth = layout.depth
        switch edge {
        case .bottom:
            return CGRect(x: layout.plateStart, y: thickness - depth, width: length, height: depth)
        case .left:
            return CGRect(x: 0, y: layout.plateStart, width: depth, height: length)
        case .right:
            return CGRect(x: thickness - depth, y: layout.plateStart, width: depth, height: length)
        }
    }

    /// A line across the dock at `along`, for the drop marker.
    func markerFrame(along: CGFloat, width: CGFloat) -> CGRect {
        let across = tileSize * 0.9
        let offset = (thickness - across) / 2
        return edge.isVertical
            ? CGRect(x: offset, y: along - width / 2, width: across, height: width)
            : CGRect(x: along - width / 2, y: offset, width: width, height: across)
    }

    // MARK: - Items

    /// Where the app is now; nil once it can no longer be found.
    func appURL(for item: DockItem, reference: DockAppReference) -> URL? {
        if let cached = resolved[item.id] { return cached }
        let url = actions.resolvedURL(for: reference)
        resolved[item.id] = .some(url)
        return url
    }

    func isMissing(_ item: DockItem, reference: DockAppReference, running: DockRunningApp?) -> Bool {
        running == nil && appURL(for: item, reference: reference) == nil
    }

    func iconPath(
        for item: DockItem, reference: DockAppReference, running: DockRunningApp?
    ) -> String {
        running?.path ?? appURL(for: item, reference: reference)?.path ?? reference.path
    }

    func badge(for bundleID: String?) -> String? {
        guard dock.content.showsBadges, let bundleID else { return nil }
        return windows.badges[bundleID]
    }

    /// The name a tile's label shows; nil for a spacer, a divider and the like.
    func name(of slot: DockSlot) -> String? {
        if let cached = names[slot.id] { return cached }
        let name: String?
        switch slot {
        case .pinned(let item, let running):
            name = running?.name ?? actions.name(of: item)
        case .running(let app):
            name = app.name
        case .minimized(let window):
            name = window.title.isEmpty ? window.appName : "\(window.title) — \(window.appName)"
        case .trash:
            name = "Trash"
        case .divider:
            name = nil
        }
        names[slot.id] = .some(name)
        return name
    }
}

extension DockEdge {
    /// Where the dock's plate sits within its panel: against the screen edge, centred along it.
    var surfaceAlignment: Alignment {
        switch self {
        case .bottom: .bottom
        case .left: .leading
        case .right: .trailing
        }
    }

    var marginEdge: Edge.Set {
        switch self {
        case .bottom: .bottom
        case .left: .leading
        case .right: .trailing
        }
    }

    /// The direction a tucked dock slides, as a multiple of its travel.
    var tuckDirection: CGSize {
        switch self {
        case .bottom: CGSize(width: 0, height: 1)
        case .left: CGSize(width: -1, height: 0)
        case .right: CGSize(width: 1, height: 0)
        }
    }
}
