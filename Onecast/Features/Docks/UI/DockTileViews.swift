import AppKit
import SwiftUI

/// One slot of a dock as drawn, laid out once at `size` (rest × `renderScale`) and then scaled and
/// moved by transforms, which are never rounded to whole points; the container owns its gestures.
struct DockTileView: View {
    let slot: DockSlot
    let model: DockSurfaceModel
    let size: CGSize
    let renderScale: CGFloat

    var body: some View {
        content
            .frame(width: size.width, height: size.height)
            .background { openedBackdrop }
            .overlay { dropHighlight }
            .opacity(model.draggingSlotID == slot.id ? 0 : 1)
            .modifier(DockTileAccessibility(slot: slot, model: model))
    }

    /// The side of an icon: a magnified tile grows across the dock as well as along it.
    private var side: CGFloat { min(size.width, size.height) }

    @ViewBuilder
    private var content: some View {
        switch slot {
        case .pinned(let item, let running):
            pinned(item, running: running)
        case .running(let app):
            DockAppTile(
                path: app.path, isMissing: false, running: app,
                badge: model.badge(for: app.bundleID), model: model, side: side,
                renderScale: renderScale)
        case .minimized(let window):
            DockMinimizedTile(
                window: window, preview: model.windows.preview(for: window.token), side: side)
        case .divider:
            DockDividerTile(model: model, size: size)
        case .trash:
            DockTrashTile(hasItems: model.trash.hasItems)
        }
    }

    @ViewBuilder
    private func pinned(_ item: DockItem, running: DockRunningApp?) -> some View {
        switch item.kind {
        case .app(let reference):
            DockAppTile(
                path: model.iconPath(for: item, reference: reference, running: running),
                isMissing: model.isMissing(item, reference: reference, running: running),
                running: running, badge: model.badge(for: running?.bundleID ?? reference.bundleID),
                model: model, side: side, renderScale: renderScale)
        case .folder(let folder):
            DockFolderTile(folder: folder, side: side)
        case .file(let path):
            EntryIconView(source: .file(stamp: 0), fileURL: URL(fileURLWithPath: path))
        case .link(let link):
            EntryIconView(source: .symbol(link.symbol ?? "globe"))
        case .shortcut:
            EntryIconView(source: .file(stamp: 0), fileURL: AppleShortcutCoordinator.applicationURL)
        case .spacer:
            Color.clear
        case .widget(let reference):
            DockWidgetTileView(
                instanceID: item.id, reference: reference, edge: model.edge,
                tileLength: model.tileSize * renderScale
            )
            .equatable()
            .simultaneousGesture(TapGesture().onEnded { model.onWidgetTap?(item.id) })
        }
    }

    @ViewBuilder
    private var openedBackdrop: some View {
        if model.openSlotID == slot.id {
            RoundedRectangle(cornerRadius: side * Self.cornerRatio, style: .continuous)
                .fill(Theme.Colors.rowHover)
        }
    }

    @ViewBuilder
    private var dropHighlight: some View {
        switch model.drop {
        case .openWith(let id) where id == slot.id:
            highlight
        case .trash:
            if case .trash = slot { highlight }
        default:
            EmptyView()
        }
    }

    private var highlight: some View {
        RoundedRectangle(cornerRadius: side * Self.cornerRatio, style: .continuous)
            .strokeBorder(Theme.Colors.dropGuideArmed, lineWidth: Self.highlightWidth)
            .background(
                RoundedRectangle(cornerRadius: side * Self.cornerRatio, style: .continuous)
                    .fill(Theme.Colors.dropGuideArmed.opacity(Self.highlightFill)))
            .allowsHitTesting(false)
    }

    /// An app icon's curvature as a share of its side.
    private static let cornerRatio: CGFloat = 0.22
    private static let highlightWidth: CGFloat = 2
    private static let highlightFill = 0.18
}

/// The lens only transforms a tile, so a tile redraws on its own inputs or observed state alone.
extension DockTileView: @MainActor Equatable {
    static func == (lhs: DockTileView, rhs: DockTileView) -> Bool {
        lhs.slot == rhs.slot && lhs.model === rhs.model && lhs.size == rhs.size
            && lhs.renderScale == rhs.renderScale
    }
}

/// An app's icon with its running dot, badge and dimming when it can no longer be found.
private struct DockAppTile: View {
    let path: String
    let isMissing: Bool
    let running: DockRunningApp?
    let badge: String?
    let model: DockSurfaceModel
    let side: CGFloat
    /// The tile is drawn this much larger than rest and scaled down, so rest sizes are scaled up.
    let renderScale: CGFloat

    private static let dotRatio: CGFloat = 0.08
    private static let minimumDot: CGFloat = 3
    private static let hiddenDotOpacity = 0.45
    private static let missingOpacity = 0.4

    var body: some View {
        EntryIconView(source: .file(stamp: 0), fileURL: URL(fileURLWithPath: path))
            .opacity(isMissing ? Self.missingOpacity : 1)
            .overlay(alignment: .topTrailing) { badgeView }
            .overlay(alignment: dotAlignment) { dot }
    }

    private var dotSize: CGFloat { max(model.tileSize * Self.dotRatio, Self.minimumDot) * renderScale }

    /// Half way between the icon and the plate's rim, which is `inset` thick.
    private var dotTravel: CGFloat { (model.inset / 2) * renderScale + dotSize / 2 }

    private var dotAlignment: Alignment { model.edge.surfaceAlignment }

    @ViewBuilder
    private var dot: some View {
        if let running {
            let direction = model.edge.tuckDirection
            Circle()
                .fill(Theme.Colors.textPrimary)
                .opacity(running.isHidden ? Self.hiddenDotOpacity : 1)
                .frame(width: dotSize, height: dotSize)
                .offset(x: direction.width * dotTravel, y: direction.height * dotTravel)
                .accessibilityHidden(true)
        }
    }

    @ViewBuilder
    private var badgeView: some View {
        if let badge {
            Text(badge)
                .font(.system(size: max(side * 0.26, 9), weight: .semibold))
                .foregroundStyle(Color.white)
                .lineLimit(1)
                .padding(.horizontal, max(side * 0.08, 4))
                .frame(minWidth: side * 0.34, minHeight: side * 0.34)
                .background(Capsule().fill(Theme.Colors.destructive))
                .offset(x: side * 0.1, y: -side * 0.1)
        }
    }
}

/// A folder: its own icon, or a flat folder in the dock colour, with an optional letter and name.
private struct DockFolderTile: View {
    let folder: DockFolderReference
    let side: CGFloat

    var body: some View {
        ZStack {
            if let color = folder.color {
                SymbolImage(name: "folder.fill", size: side * 0.92)
                    .foregroundStyle(color.swatch)
                    .frame(width: side, height: side)
            } else {
                EntryIconView(source: .file(stamp: 0), fileURL: URL(fileURLWithPath: folder.path))
            }
            if let letter = folder.letter, !letter.isEmpty {
                Text(String(letter.prefix(1)))
                    .font(.system(size: side * 0.34, weight: .bold, design: .rounded))
                    .foregroundStyle(Color.white)
                    .shadow(color: .black.opacity(0.35), radius: 1, y: 0.5)
                    .offset(y: folder.showsName ? -side * 0.1 : side * 0.04)
            }
        }
        .frame(width: side, height: side)
        .overlay(alignment: .bottom) {
            if folder.showsName {
                Text(folder.customName ?? URL(fileURLWithPath: folder.path).lastPathComponent)
                    .font(.system(size: max(side * 0.17, 8), weight: .semibold))
                    .foregroundStyle(Color.white)
                    .shadow(color: .black.opacity(0.6), radius: 1.5, y: 0.5)
                    .lineLimit(1)
                    .minimumScaleFactor(0.6)
                    .padding(.horizontal, side * 0.06)
                    .padding(.bottom, side * 0.1)
            }
        }
    }
}

/// A minimized window: its snapshot when there is one, with the app's icon in the corner.
private struct DockMinimizedTile: View {
    let window: DockMinimizedWindow
    let preview: NSImage?
    let side: CGFloat

    var body: some View {
        ZStack(alignment: .bottomTrailing) {
            if let preview {
                Image(nsImage: preview)
                    .resizable()
                    .scaledToFit()
                    .clipShape(RoundedRectangle(cornerRadius: side * 0.1, style: .continuous))
                    .frame(width: side, height: side)
            } else {
                EntryIconView(source: .symbol("macwindow"))
            }
            EntryIconView(source: .file(stamp: 0), fileURL: URL(fileURLWithPath: window.appPath))
                .frame(width: side * 0.42, height: side * 0.42)
        }
        .frame(width: side, height: side)
    }
}

private struct DockTrashTile: View {
    let hasItems: Bool

    var body: some View {
        Image(nsImage: NSImage(named: hasItems ? NSImage.trashFullName : NSImage.trashEmptyName) ?? NSImage())
            .resizable()
            .scaledToFit()
    }
}

/// The hairline between groups, across the dock's thickness.
private struct DockDividerTile: View {
    let model: DockSurfaceModel
    let size: CGSize

    private static let lengthRatio: CGFloat = 0.62

    var body: some View {
        let across = model.tileSize * Self.lengthRatio
        let line = max(Theme.Size.hairline, model.tileSize * 0.03)
        Capsule()
            .fill(Theme.Colors.border)
            .frame(
                width: model.edge.isVertical ? across : line,
                height: model.edge.isVertical ? line : across)
            .frame(width: size.width, height: size.height)
    }
}

/// A tile's name and press for VoiceOver; the tile has no gesture of its own to expose.
private struct DockTileAccessibility: ViewModifier {
    let slot: DockSlot
    let model: DockSurfaceModel

    func body(content: Content) -> some View {
        if let name = model.name(of: slot), isActionable {
            content
                .accessibilityElement(children: .ignore)
                .accessibilityLabel(name)
                .accessibilityAddTraits(.isButton)
                .accessibilityAction { model.onActivate?(slot.id) }
        } else {
            content
        }
    }

    /// A widget keeps its own accessibility tree; spacers and dividers have nothing to press.
    private var isActionable: Bool {
        switch slot {
        case .pinned(let item, _):
            switch item.kind {
            case .spacer, .widget: false
            default: true
            }
        case .divider: false
        default: true
        }
    }
}
