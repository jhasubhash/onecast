import AppKit
import OnecastPluginKit
import SwiftUI

/// Sizes that only the Docks pane draws, kept beside it rather than bolted onto `Theme`.
enum DockSettingsMetrics {
    static let swatch: CGFloat = 16
    /// One tile in an items strip; spacers and widgets scale from it.
    static let stripTile: CGFloat = 40
    static let stripGap = Theme.Spacing.sm
    static let stripInset = Theme.Spacing.md
    static let dropBar: CGFloat = 3
    static let nativeTile: CGFloat = 28
    static let nameFieldWidth: CGFloat = 200
    static let letterFieldWidth: CGFloat = 56
    static let widgetRowIcon: CGFloat = 28
    static let widgetSheetListHeight: CGFloat = 360
    static let nativeSlot: CGFloat = 14
}

extension DockEdge {
    var settingsTitle: String {
        switch self {
        case .left: "Left"
        case .bottom: "Bottom"
        case .right: "Right"
        }
    }

    var settingsSymbol: String {
        switch self {
        case .left: "sidebar.left"
        case .bottom: "dock.rectangle"
        case .right: "sidebar.right"
        }
    }

    /// The order the pane lists edges in, which is not the model's declaration order.
    static let settingsOrder: [DockEdge] = [.left, .bottom, .right]
}

extension DockMaterial {
    var settingsTitle: String {
        switch self {
        case .glassRegular: "Liquid Glass"
        case .glassClear: "Clear glass"
        case .frosted: "Frosted"
        }
    }
}

extension DockLayer {
    var settingsTitle: String {
        switch self {
        case .floating: "Above windows"
        case .desktop: "On the desktop"
        }
    }
}

extension NativeDockMode {
    var settingsTitle: String {
        switch self {
        case .macOSOnly: "macOS Dock only"
        case .both: "macOS Dock + custom docks"
        case .customMain: "Custom docks as main Dock"
        }
    }

    var settingsDetail: String {
        switch self {
        case .macOSOnly: "Custom docks stay off; Onecast only saves and switches macOS Dock layouts."
        case .both: "Custom docks sit beside the macOS Dock, which stays as you set it."
        case .customMain: "Custom docks replace the macOS Dock while Onecast runs."
        }
    }
}

extension NativeDockHiding {
    var settingsTitle: String {
        switch self {
        case .reachable: "Reachable at the screen edge"
        case .suppressed: "Hidden (never appears)"
        }
    }

    var settingsDetail: String {
        switch self {
        case .reachable: "The macOS Dock hides until the pointer reaches its screen edge."
        case .suppressed: "The macOS Dock never appears, even at its screen edge."
        }
    }
}

extension DockSpacerSize {
    var settingsTitle: String {
        switch self {
        case .small: "Small Spacer"
        case .regular: "Regular Spacer"
        }
    }
}

extension DockWidgetSpan {
    /// The kit's size and the model's span are the same three steps under two names.
    init(_ size: DockWidgetSize) {
        switch size {
        case .compact: self = .compact
        case .wide: self = .wide
        case .expanded: self = .expanded
        }
    }

    var settingsTitle: String {
        switch self {
        case .compact: "Compact"
        case .wide: "Wide"
        case .expanded: "Expanded"
        }
    }

    var settingsDetail: String {
        tiles == 1 ? "1 tile" : "\(tiles) tiles"
    }
}

extension DockColor {
    var title: String { rawValue.capitalized }

    var swatch: Color {
        switch self {
        case .blue: Color(nsColor: .systemBlue)
        case .purple: Color(nsColor: .systemPurple)
        case .pink: Color(nsColor: .systemPink)
        case .red: Color(nsColor: .systemRed)
        case .orange: Color(nsColor: .systemOrange)
        case .yellow: Color(nsColor: .systemYellow)
        case .green: Color(nsColor: .systemGreen)
        case .teal: Color(nsColor: .systemTeal)
        case .graphite: Color(nsColor: .systemGray)
        }
    }
}

/// A connected display a dock can be pinned to.
struct DockDisplayOption: Identifiable, Hashable {
    let key: String
    let name: String
    var id: String { key }
}

@MainActor
enum DockDisplays {
    /// Two identical monitors share a name, so a repeat gets a number to be told apart.
    static func connected() -> [DockDisplayOption] {
        var seen: [String: Int] = [:]
        return NSScreen.screens.map { screen in
            let name = screen.localizedName
            let count = (seen[name] ?? 0) + 1
            seen[name] = count
            return DockDisplayOption(
                key: screen.displayKey, name: count > 1 ? "\(name) (\(count))" : name)
        }
    }

    static func name(for key: String?, in options: [DockDisplayOption]) -> String {
        guard let key else { return "Main display" }
        return options.first { $0.key == key }?.name ?? "Disconnected display"
    }
}

/// Where along its edge a dock sits, as the three stops the segmented control offers.
enum DockAlignmentPreset: CaseIterable {
    case start, centre, end

    var alignment: Double {
        switch self {
        case .start: 0
        case .centre: 0.5
        case .end: 1
        }
    }

    /// A bottom dock starts at the left; a side dock starts at the top.
    func title(on edge: DockEdge) -> String {
        switch self {
        case .start: edge.isVertical ? "Top" : "Left"
        case .centre: "Centre"
        case .end: edge.isVertical ? "Bottom" : "Right"
        }
    }

    init?(alignment: Double) {
        guard let match = Self.allCases.first(where: { abs($0.alignment - alignment) < 0.001 })
        else { return nil }
        self = match
    }
}

/// What an item says about itself in a list or a tooltip.
@MainActor
enum DockItemPresentation {
    static func title(of item: DockItem, widgets: DockWidgetManager) -> String {
        switch item.kind {
        case .app(let reference):
            return fileName(reference.path, dropsExtension: true)
        case .folder(let reference):
            if let name = reference.customName, !name.isEmpty { return name }
            return fileName(reference.path)
        case .file(let path): return fileName(path)
        case .link(let reference): return reference.title
        case .spacer(let size): return size.settingsTitle
        case .widget(let reference):
            return widgets.descriptor(id: reference.widgetID)?.metadata.name ?? reference.widgetID
        case .shortcut(let name): return name
        }
    }

    static func kindName(of item: DockItem) -> String {
        switch item.kind {
        case .app: "App"
        case .folder: "Folder"
        case .file: "File"
        case .link: "Link"
        case .spacer: "Spacer"
        case .widget: "Widget"
        case .shortcut: "Shortcut"
        }
    }

    static func fileName(_ path: String, dropsExtension: Bool = false) -> String {
        let url = URL(fileURLWithPath: path)
        return dropsExtension ? url.deletingPathExtension().lastPathComponent : url.lastPathComponent
    }
}
