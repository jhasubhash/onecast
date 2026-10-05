import OnecastPluginKit
import SwiftUI

/// A widget in its dock slot, drawn as a card inside the dock's plate, or a placeholder; the
/// surface owns the click. The card is drawn here, once, so a widget never draws its own: its
/// corner is concentric with the plate's. Needs `AppCore`.
struct DockWidgetTileView: View {
    /// A placeholder glyph's size as a share of the tile's side.
    private static let glyphRatio: CGFloat = 0.4
    private static let headlineLimit = 160

    @Environment(AppCore.self) private var core
    let instanceID: UUID
    let reference: DockWidgetReference
    let edge: DockEdge
    let tileLength: CGFloat

    /// The slot a widget of `span` takes: `tileLength` across the dock, the slot's extent along it.
    static func size(span: DockWidgetSpan, edge: DockEdge, tileLength: CGFloat) -> CGSize {
        let extent: DockGeometry.Extent = span == .compact ? .tile : .span(span.tiles)
        let along = extent.length(tileSize: tileLength)
        return edge.isVertical
            ? CGSize(width: tileLength, height: along) : CGSize(width: along, height: tileLength)
    }

    /// The plate's corner less the padding around the card, so the two curves run parallel.
    static func cornerRadius(tileLength: CGFloat) -> CGFloat {
        DockPlateShape.cardRadius(tileSize: tileLength)
    }

    var body: some View {
        tile(in: core.dockCoordinator.widgets)
    }

    private func tile(in widgets: DockWidgetManager) -> some View {
        let size = Self.size(span: reference.span, edge: edge, tileLength: tileLength)
        let widget = widgets.widget(for: instanceID, widgetID: reference.widgetID)
        let state = widgets.state(for: instanceID)
        // Read, not used: a Settings edit re-renders the tile so the widget reads its new values.
        _ = widgets.preferencesRevision
        return Group {
            if let widget {
                widget.tile(
                    context: widgets.context(
                        instanceID: instanceID, span: reference.span, edge: edge,
                        tileLength: tileLength))
            } else {
                placeholder(for: state)
            }
        }
        .frame(width: size.width, height: size.height)
        .background(
            RoundedRectangle(
                cornerRadius: Self.cornerRadius(tileLength: tileLength), style: .continuous
            )
            .fill(Theme.Colors.controlSurface)
        )
        .clipShape(
            RoundedRectangle(
                cornerRadius: Self.cornerRadius(tileLength: tileLength), style: .continuous))
        .tooltip(widget == nil ? Self.tooltip(for: state) : nil)
    }

    private func placeholder(for state: DockWidgetInstanceState) -> some View {
        ZStack {
            switch state {
            case .loading:
                ProgressView()
                    .controlSize(.small)
                    .accessibilityLabel("Loading widget")
            case .failed:
                SymbolImage(name: "exclamationmark.triangle.fill", size: tileLength * Self.glyphRatio)
                    .foregroundStyle(Theme.Colors.warning)
                    .accessibilityLabel("Widget failed to load")
            case .unavailable:
                SymbolImage(name: "lock.fill", size: tileLength * Self.glyphRatio)
                    .foregroundStyle(Theme.Colors.textSecondary)
                    .accessibilityLabel("Third-party DockWidgets are off")
            case .ready:
                EmptyView()
            }
        }
    }

    private static func tooltip(for state: DockWidgetInstanceState) -> String? {
        switch state {
        case .failed(let message): headline(of: message)
        case .unavailable: "Third-party DockWidgets are off — allow them in Settings › Docks."
        case .loading, .ready: nil
        }
    }

    /// The compiler's first error, or the message's first line: a tooltip can't hold a whole log.
    private static func headline(of message: String) -> String {
        let lines = message.split(whereSeparator: \.isNewline)
        let line = lines.first { $0.contains("error:") } ?? lines.first ?? Substring(message)
        return line.count <= headlineLimit ? String(line) : String(line.prefix(headlineLimit)) + "…"
    }
}

/// Redraws on its own inputs or observed state, never because the lens is scaling its slot.
extension DockWidgetTileView: @MainActor Equatable {
    static func == (lhs: DockWidgetTileView, rhs: DockWidgetTileView) -> Bool {
        lhs.instanceID == rhs.instanceID && lhs.reference == rhs.reference && lhs.edge == rhs.edge
            && lhs.tileLength == rhs.tileLength
    }
}
