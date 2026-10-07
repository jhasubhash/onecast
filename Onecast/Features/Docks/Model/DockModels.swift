import Foundation

/// The screen edge a custom dock hugs.
enum DockEdge: String, Codable, Sendable, CaseIterable {
    case bottom, left, right

    var isVertical: Bool { self != .bottom }
}

/// The backdrop a dock draws. The glass styles map to `NSGlassEffectView`; frosted is the blur.
enum DockMaterial: String, Codable, Sendable, CaseIterable {
    case glassRegular, glassClear, frosted
}

/// Above app windows, as the macOS Dock sits, or pinned just above the desktop behind them.
enum DockLayer: String, Codable, Sendable, CaseIterable {
    case floating, desktop
}

/// The named tint a layout, setup or folder wears; resolved to a colour in the UI layer.
enum DockColor: String, Codable, Sendable, CaseIterable {
    case blue, purple, pink, red, orange, yellow, green, teal, graphite
}

enum DockSpacerSize: String, Codable, Sendable, CaseIterable {
    case small, regular
}

/// How much of the dock's length a widget takes: one tile, two, or four.
enum DockWidgetSpan: String, Codable, Sendable, CaseIterable {
    case compact, wide, expanded

    var tiles: Int {
        switch self {
        case .compact: 1
        case .wide: 2
        case .expanded: 4
        }
    }
}

struct DockAppearance: Codable, Sendable, Hashable {
    var material: DockMaterial = .glassRegular
    /// Points per tile, before interface-size scaling.
    var tileSize: Double = 48
    /// The hovered tile's size; at or below `tileSize` magnification is off.
    var magnifiedSize: Double = 48
    var autoHides = false
    var showsHandleWhenHidden = true
    var layer: DockLayer = .floating
    var hidesWhenMacOSDockAppears = false

    static let tileSizeRange: ClosedRange<Double> = 24...128
    static let magnifiedSizeRange: ClosedRange<Double> = 24...192

    var magnifies: Bool { magnifiedSize > tileSize }

    mutating func sanitize() {
        tileSize = tileSize.clamped(to: Self.tileSizeRange)
        magnifiedSize = max(magnifiedSize.clamped(to: Self.magnifiedSizeRange), tileSize)
    }
}

/// The automatic tiles a dock adds around its pinned items.
struct DockContentOptions: Codable, Sendable, Hashable {
    var showsRunningApps = true
    var showsMinimizedWindows = false
    var showsTrash = true
    var clickFocusedAppMinimizes = false
    var showsBadges = false
}

struct DockPlacement: Codable, Sendable, Hashable {
    /// `NSScreen.displayKey`; nil follows whichever display holds the menu bar.
    var displayKey: String?
    var edge: DockEdge = .bottom
    /// Where along the edge the dock's centre sits, 0 = start, 1 = end.
    var alignment: Double = 0.5

    mutating func sanitize() {
        alignment = alignment.clamped(to: 0...1)
    }
}

/// A picture drawn in place of an app's own icon, so a dock can follow a custom theme.
enum DockCustomIcon: Codable, Sendable, Hashable {
    /// An image file (PNG, JPEG, ICNS, PDF, SVG), drawn at the size of an app icon.
    case image(path: String)
    /// An SF Symbol on an app-icon-shaped tile; the colour fills the tile, none leaves it plain.
    case symbol(name: String, color: DockColor?)
}

struct DockAppReference: Codable, Sendable, Hashable {
    var bundleID: String?
    /// The bundle's path when it was added; re-resolved through `bundleID` if it moved.
    var path: String
    /// Drawn in the dock instead of the app's own icon; nil keeps the app's.
    var customIcon: DockCustomIcon?
}

struct DockFolderReference: Codable, Sendable, Hashable {
    var path: String
    /// Shown in place of the folder's own name; dock-only, never written to disk.
    var customName: String?
    var color: DockColor?
    /// One character drawn over the folder icon.
    var letter: String?
    var showsName = false
}

struct DockLinkReference: Codable, Sendable, Hashable {
    var url: String
    var title: String
    /// An SF Symbol in place of the site's icon.
    var symbol: String?
}

struct DockWidgetReference: Codable, Sendable, Hashable {
    /// `builtin.<name>` for a first-party widget, else the DockWidget manifest's `identifier`.
    var widgetID: String
    var span: DockWidgetSpan = .compact
}

/// One thing pinned to a dock. The item's `id` doubles as a widget's instance id.
struct DockItem: Identifiable, Codable, Sendable, Hashable {
    enum Kind: Codable, Sendable, Hashable {
        case app(DockAppReference)
        case folder(DockFolderReference)
        case file(path: String)
        case link(DockLinkReference)
        case spacer(DockSpacerSize)
        case widget(DockWidgetReference)
        /// An Apple Shortcut, run by name.
        case shortcut(name: String)
    }

    var id: UUID
    var kind: Kind

    init(id: UUID = UUID(), kind: Kind) {
        self.id = id
        self.kind = kind
    }

    /// A copy with a fresh identity, so it cannot share a widget instance's preferences.
    var copy: DockItem { DockItem(kind: kind) }
}

/// A named arrangement of items; a dock shows one at a time and switches between its own.
struct DockLayout: Identifiable, Codable, Sendable, Hashable {
    var id: UUID
    var name: String
    var color: DockColor
    var items: [DockItem]

    init(id: UUID = UUID(), name: String, color: DockColor = .blue, items: [DockItem] = []) {
        self.id = id
        self.name = name
        self.color = color
        self.items = items
    }
}

/// One custom dock: its own window, edge, look and layouts. Several can be visible at once.
struct CustomDock: Identifiable, Codable, Sendable, Hashable {
    var id: UUID
    var name: String
    var isVisible: Bool
    var placement: DockPlacement
    var appearance: DockAppearance
    var content: DockContentOptions
    /// Never empty once sanitized: a dock always has something to show.
    var layouts: [DockLayout]
    var activeLayoutID: UUID

    init(
        id: UUID = UUID(), name: String, isVisible: Bool = true,
        placement: DockPlacement = DockPlacement(), appearance: DockAppearance = DockAppearance(),
        content: DockContentOptions = DockContentOptions(), layouts: [DockLayout] = []
    ) {
        let layouts = layouts.isEmpty ? [DockLayout(name: "Default")] : layouts
        self.id = id
        self.name = name
        self.isVisible = isVisible
        self.placement = placement
        self.appearance = appearance
        self.content = content
        self.layouts = layouts
        activeLayoutID = layouts[0].id
    }

    var activeLayout: DockLayout {
        layouts.first { $0.id == activeLayoutID } ?? layouts[0]
    }

    /// The layout `offset` steps from the active one, wrapping; a swipe passes ±1.
    func layout(steppedBy offset: Int) -> DockLayout {
        guard let index = layouts.firstIndex(where: { $0.id == activeLayoutID }) else {
            return layouts[0]
        }
        let count = layouts.count
        return layouts[((index + offset) % count + count) % count]
    }
}

/// A tile in the macOS Dock's `persistent-apps`, kept verbatim so a re-apply loses nothing.
struct NativeDockTile: Codable, Sendable, Hashable {
    enum Kind: Codable, Sendable, Hashable {
        case app(bundleID: String?, path: String, label: String)
        case spacer(DockSpacerSize)
        /// A tile type this model does not interpret, re-written exactly as captured.
        case other(type: String)
    }

    var kind: Kind
    /// The tile's own dictionary as a binary property list; nil for a tile authored in Onecast.
    var raw: Data?
}

/// A saved arrangement of the macOS Dock's pinned apps and spacers.
struct NativeDockLayout: Identifiable, Codable, Sendable, Hashable {
    var id: UUID
    var name: String
    var color: DockColor
    var tiles: [NativeDockTile]

    init(id: UUID = UUID(), name: String, color: DockColor = .graphite, tiles: [NativeDockTile]) {
        self.id = id
        self.name = name
        self.color = color
        self.tiles = tiles
    }
}

/// A whole setup switched at once: the macOS Dock's layout and each custom dock's state.
struct DockSetup: Identifiable, Codable, Sendable, Hashable {
    struct DockState: Codable, Sendable, Hashable {
        var dockID: UUID
        var isVisible: Bool
        /// Nil keeps whatever layout the dock already shows.
        var layoutID: UUID?
    }

    var id: UUID
    var name: String
    var color: DockColor
    /// Nil leaves the macOS Dock as it is.
    var nativeLayoutID: UUID?
    /// A dock not listed here is left alone by the switch.
    var docks: [DockState]

    init(
        id: UUID = UUID(), name: String, color: DockColor = .blue, nativeLayoutID: UUID? = nil,
        docks: [DockState] = []
    ) {
        self.id = id
        self.name = name
        self.color = color
        self.nativeLayoutID = nativeLayoutID
        self.docks = docks
    }
}

/// How Onecast and the macOS Dock share the screen.
enum NativeDockMode: String, Codable, Sendable, CaseIterable {
    /// Custom docks off; Onecast only saves and switches the macOS Dock's layouts.
    case macOSOnly
    /// Both on screen; the macOS Dock is left exactly as the user set it.
    case both
    /// Custom docks are the main dock; the macOS Dock is hidden while Onecast runs.
    case customMain
}

/// How hard `customMain` hides the macOS Dock.
enum NativeDockHiding: String, Codable, Sendable, CaseIterable {
    /// Auto-hidden: still revealed when the pointer reaches its edge.
    case reachable
    /// Auto-hidden behind a reveal delay long enough that it never appears in practice.
    case suppressed
}

/// Everything the Docks feature persists, as one value so a backup and a store share a shape.
struct DockConfiguration: Codable, Sendable, Hashable {
    var docks: [CustomDock] = []
    var nativeLayouts: [NativeDockLayout] = []
    var setups: [DockSetup] = []
    var nativeMode: NativeDockMode = .both
    var nativeHiding: NativeDockHiding = .reachable
    /// The native layout last applied, so edits in the real Dock can be saved back into it.
    var activeNativeLayoutID: UUID?
    var savesNativeDockChanges = false
    var activeSetupID: UUID?

    init() {}

    /// Decodes field by field, so a key added later never discards a whole saved configuration.
    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        let defaults = DockConfiguration()
        docks = try c.decodeIfPresent([CustomDock].self, forKey: .docks) ?? defaults.docks
        nativeLayouts =
            try c.decodeIfPresent([NativeDockLayout].self, forKey: .nativeLayouts)
            ?? defaults.nativeLayouts
        setups = try c.decodeIfPresent([DockSetup].self, forKey: .setups) ?? defaults.setups
        nativeMode =
            (try? c.decodeIfPresent(NativeDockMode.self, forKey: .nativeMode)) ?? defaults.nativeMode
        nativeHiding =
            (try? c.decodeIfPresent(NativeDockHiding.self, forKey: .nativeHiding))
            ?? defaults.nativeHiding
        activeNativeLayoutID = try c.decodeIfPresent(UUID.self, forKey: .activeNativeLayoutID)
        savesNativeDockChanges =
            try c.decodeIfPresent(Bool.self, forKey: .savesNativeDockChanges)
            ?? defaults.savesNativeDockChanges
        activeSetupID = try c.decodeIfPresent(UUID.self, forKey: .activeSetupID)
    }

    /// Repairs references a hand edit or an import left dangling, rather than rejecting the whole.
    mutating func sanitize() {
        var dockIDs = Set<UUID>()
        docks = docks.compactMap { dock in
            guard dockIDs.insert(dock.id).inserted else { return nil }
            var dock = dock
            dock.name = dock.name.trimmingCharacters(in: .whitespacesAndNewlines)
            if dock.name.isEmpty { dock.name = "Dock" }
            dock.placement.sanitize()
            dock.appearance.sanitize()
            var layoutIDs = Set<UUID>()
            dock.layouts = dock.layouts.filter { layoutIDs.insert($0.id).inserted }
            if dock.layouts.isEmpty { dock.layouts = [DockLayout(name: "Default")] }
            if !dock.layouts.contains(where: { $0.id == dock.activeLayoutID }) {
                dock.activeLayoutID = dock.layouts[0].id
            }
            return dock
        }
        var nativeIDs = Set<UUID>()
        nativeLayouts = nativeLayouts.filter { nativeIDs.insert($0.id).inserted }
        if let id = activeNativeLayoutID, !nativeIDs.contains(id) { activeNativeLayoutID = nil }
        var setupIDs = Set<UUID>()
        setups = setups.compactMap { setup in
            guard setupIDs.insert(setup.id).inserted else { return nil }
            var setup = setup
            if let id = setup.nativeLayoutID, !nativeIDs.contains(id) { setup.nativeLayoutID = nil }
            setup.docks = setup.docks.compactMap { state in
                guard let dock = docks.first(where: { $0.id == state.dockID }) else { return nil }
                var state = state
                if let id = state.layoutID, !dock.layouts.contains(where: { $0.id == id }) {
                    state.layoutID = nil
                }
                return state
            }
            return setup
        }
        if let id = activeSetupID, !setupIDs.contains(id) { activeSetupID = nil }
    }
}

extension Comparable {
    fileprivate func clamped(to range: ClosedRange<Self>) -> Self {
        min(max(self, range.lowerBound), range.upperBound)
    }
}
