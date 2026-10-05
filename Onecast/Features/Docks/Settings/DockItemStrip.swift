import AppKit
import SwiftUI
import UniformTypeIdentifiers

/// The layout drawn as a dock: items in order, a drag reorders, a click selects one to edit.
struct DockItemStrip: View {
    let items: [DockItem]
    @Binding var selection: UUID?
    let onMove: (_ source: Int, _ destination: Int) -> Void

    @Environment(AppCore.self) private var core
    @State private var dragging: UUID?
    @State private var insertion: Int?
    @State private var viewportWidth: CGFloat = 0

    var body: some View {
        ScrollView(.horizontal) {
            HStack(spacing: DockSettingsMetrics.stripGap) {
                ForEach(Array(items.enumerated()), id: \.element.id) { index, item in
                    tile(item, at: index)
                }
                trailingZone
            }
            .frame(
                minWidth: max(viewportWidth - 2 * DockSettingsMetrics.stripInset, 0),
                alignment: .leading
            )
            .padding(DockSettingsMetrics.stripInset)
        }
        .onGeometryChange(for: CGFloat.self) { $0.size.width } action: { viewportWidth = $0 }
        .scrollIndicators(.automatic)
        .background(
            RoundedRectangle(cornerRadius: Theme.Radius.card, style: .continuous)
                .fill(Theme.Colors.cardFill)
        )
        .overlay(
            RoundedRectangle(cornerRadius: Theme.Radius.card, style: .continuous)
                .strokeBorder(Theme.Colors.cardStroke)
        )
        .accessibilityElement(children: .contain)
        .accessibilityLabel("Layout items")
    }

    private func tile(_ item: DockItem, at index: Int) -> some View {
        let widgets = core.dockCoordinator.widgets
        let title = DockItemPresentation.title(of: item, widgets: widgets)
        let isSelected = item.id == selection
        let width = Self.width(of: item)
        return Button {
            selection = isSelected ? nil : item.id
        } label: {
            DockItemGlyph(item: item, widgets: widgets, size: DockSettingsMetrics.stripTile)
                .frame(width: width, height: DockSettingsMetrics.stripTile)
                .background(
                    RoundedRectangle(cornerRadius: Theme.Radius.menu, style: .continuous)
                        .fill(isSelected ? Theme.Colors.selection : Color.clear)
                )
                .overlay(
                    RoundedRectangle(cornerRadius: Theme.Radius.menu, style: .continuous)
                        .strokeBorder(Color.accentColor, lineWidth: isSelected ? 2 : 0)
                )
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .help("\(title) — drag to reorder")
        .overlay(alignment: .leading) { dropBar(visible: insertion == index) }
        .onDrag {
            dragging = item.id
            return NSItemProvider(object: item.id.uuidString as NSString)
        }
        .onDrop(
            of: [.plainText],
            delegate: StripDropDelegate(
                index: index, width: width, items: items, dragging: $dragging,
                insertion: $insertion, onMove: onMove)
        )
        .accessibilityLabel(title)
        .accessibilityValue(DockItemPresentation.kindName(of: item))
        .accessibilityAddTraits(isSelected ? .isSelected : [])
        .accessibilityAction(named: "Move earlier") { move(index, by: -1) }
        .accessibilityAction(named: "Move later") { move(index, by: 1) }
    }

    /// The strip's empty end, so an item can be dropped after the last one.
    private var trailingZone: some View {
        Color.clear
            .frame(minWidth: DockSettingsMetrics.stripTile, maxWidth: .infinity)
            .frame(height: DockSettingsMetrics.stripTile)
            .overlay(alignment: .leading) {
                if items.isEmpty {
                    Text("Nothing here yet. Add apps, folders, links or widgets below.")
                        .font(.callout)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                        .fixedSize()
                }
            }
            .overlay(alignment: .leading) { dropBar(visible: insertion == items.count) }
            .onDrop(
                of: [.plainText],
                delegate: StripDropDelegate(
                    index: items.count, width: nil, items: items, dragging: $dragging,
                    insertion: $insertion, onMove: onMove)
            )
    }

    private func dropBar(visible: Bool) -> some View {
        Capsule()
            .fill(Color.accentColor)
            .frame(width: DockSettingsMetrics.dropBar, height: DockSettingsMetrics.stripTile)
            .offset(x: -(DockSettingsMetrics.stripGap + DockSettingsMetrics.dropBar) / 2)
            .opacity(visible ? 1 : 0)
            .allowsHitTesting(false)
    }

    private func move(_ index: Int, by offset: Int) {
        let destination = offset < 0 ? index - 1 : index + 2
        guard (0...items.count).contains(destination) else { return }
        onMove(index, destination)
    }

    /// What an item occupies along the strip, at the dock's own proportions.
    static func width(of item: DockItem) -> CGFloat {
        let tile = DockSettingsMetrics.stripTile
        switch item.kind {
        case .spacer(.small): return tile / 2
        case .widget(let reference):
            let tiles = CGFloat(reference.span.tiles)
            return tile * tiles + DockSettingsMetrics.stripGap * (tiles - 1)
        default: return tile
        }
    }
}

/// Where a drop lands: before the tile under the pointer's left half, after it on its right.
private struct StripDropDelegate: DropDelegate {
    let index: Int
    /// Nil for the trailing zone, which only ever lands at its own index.
    let width: CGFloat?
    let items: [DockItem]
    @Binding var dragging: UUID?
    @Binding var insertion: Int?
    let onMove: (Int, Int) -> Void

    func validateDrop(info: DropInfo) -> Bool { dragging != nil }

    func dropEntered(info: DropInfo) {
        insertion = target(for: info)
    }

    func dropUpdated(info: DropInfo) -> DropProposal? {
        insertion = target(for: info)
        return DropProposal(operation: .move)
    }

    func dropExited(info: DropInfo) {
        if insertion == index || insertion == index + 1 { insertion = nil }
    }

    func performDrop(info: DropInfo) -> Bool {
        defer {
            dragging = nil
            insertion = nil
        }
        guard let dragging, let destination = insertion,
            let source = items.firstIndex(where: { $0.id == dragging })
        else { return false }
        onMove(source, destination)
        return true
    }

    private func target(for info: DropInfo) -> Int {
        guard let width else { return index }
        return info.location.x > width / 2 ? index + 1 : index
    }
}

/// One item as the dock would draw it, scaled to `size`.
struct DockItemGlyph: View {
    let item: DockItem
    let widgets: DockWidgetManager
    let size: CGFloat

    var body: some View {
        switch item.kind {
        case .app(let reference):
            DockFileIcon(path: reference.path, bundleID: reference.bundleID, size: size)
        case .file(let path):
            DockFileIcon(path: path, size: size)
        case .folder(let reference):
            folder(reference)
        case .link(let reference):
            DockSymbolTile(name: Self.linkSymbol(reference), size: size)
        case .shortcut:
            DockSymbolTile(name: AppleShortcut.sfSymbol, size: size)
        case .spacer:
            RoundedRectangle(cornerRadius: Theme.Radius.menu, style: .continuous)
                .strokeBorder(Theme.Colors.border, style: StrokeStyle(lineWidth: 1, dash: [3, 3]))
                .accessibilityHidden(true)
        case .widget(let reference):
            RoundedRectangle(cornerRadius: Theme.Radius.row, style: .continuous)
                .fill(Theme.Colors.controlSurface)
                .overlay {
                    SymbolImage(
                        name: widgets.descriptor(id: reference.widgetID)?.metadata.icon
                            ?? "square.grid.2x2",
                        size: size * 0.5
                    )
                    .foregroundStyle(.secondary)
                }
                .accessibilityHidden(true)
        }
    }

    /// A tinted folder with its letter stands in for the dock's own drawing of one.
    @ViewBuilder
    private func folder(_ reference: DockFolderReference) -> some View {
        if reference.color == nil, reference.letter == nil {
            DockFileIcon(path: reference.path, size: size)
        } else {
            ZStack {
                if let color = reference.color {
                    Image(systemName: "folder.fill")
                        .resizable()
                        .scaledToFit()
                        .foregroundStyle(color.swatch)
                } else {
                    DockFileIcon(path: reference.path, size: size)
                }
                if let letter = reference.letter {
                    Text(letter)
                        .font(.system(size: size * 0.4, weight: .bold, design: .rounded))
                        .foregroundStyle(.white)
                        .offset(y: size * 0.04)
                }
            }
            .frame(width: size, height: size)
        }
    }

    /// The site's own icon is the dock's to fetch; the editor stands a globe in for it.
    static func linkSymbol(_ reference: DockLinkReference) -> String {
        guard let symbol = reference.symbol, !symbol.isEmpty else { return "globe" }
        return symbol
    }
}
