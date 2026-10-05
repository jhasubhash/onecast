import AppKit
import SwiftUI

/// One dock as drawn: the plate and its tiles, anchored to the screen edge in a panel that is
/// larger than the plate whenever the lens needs room.
struct DockView: View {
    let model: DockSurfaceModel
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private static let slide = Animation.smooth(duration: 0.28)

    var body: some View {
        DockStripView(model: model)
            .offset(tuckOffset)
            .animation(reduceMotion ? nil : Self.slide, value: model.isTucked)
            .padding(model.edge.marginEdge, DockGeometry.edgeMargin)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: model.edge.surfaceAlignment)
    }

    /// Slid far enough that only the handle is left inside the panel's edge.
    private var tuckOffset: CGSize {
        guard model.isTucked else { return .zero }
        let travel = model.thickness + DockGeometry.edgeMargin - model.tuckedVisible
        let direction = model.edge.tuckDirection
        return CGSize(width: direction.width * travel, height: direction.height * travel)
    }
}

/// The plate and its tiles, redrawn each display frame the surface eases the lens or the pointer.
private struct DockStripView: View {
    let model: DockSurfaceModel

    private var lens: Double { model.lens }

    private static let markerWidth: CGFloat = 3
    private static let arrival = Animation.smooth(duration: 0.25)
    /// Past this, a widget counts as growing and is drawn at its peak size instead of its rest one.
    private static let growingScale: CGFloat = 1.001
    /// The grabber's length across the dock, as a share of its thickness, and its weight.
    private static let handleLengthRatio: CGFloat = 0.28
    private static let handleWeightRatio: CGFloat = 0.06
    private static let minimumHandleWeight: CGFloat = 3
    /// The faintest alpha the window server still counts as part of the window, not click-through.
    private static let hoverAlpha = 1.0 / 255.0

    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private struct Placed: Identifiable {
        let slot: DockSlot
        let tile: DockStripLayout.Tile
        var id: String { slot.id }
    }

    var body: some View {
        let slots = model.slots
        let layout = model.layout(lens: lens, slots: slots)
        let placed = zip(slots, layout.tiles).map { Placed(slot: $0, tile: $1) }
        let size = model.restSize
        ZStack(alignment: .topLeading) {
            hoverCover(layout)
            plate(layout)
            tiles(placed, layout: layout)
            marker(layout, slots: slots)
        }
        .frame(width: size.width, height: size.height, alignment: .topLeading)
        .animation(reduceMotion ? nil : Self.arrival, value: slots.map(\.id))
    }

    /// Keeps the pointer on the dock over a magnified strip's gaps and tops, which are clear.
    @ViewBuilder
    private func hoverCover(_ layout: DockStripLayout) -> some View {
        if lens > 0 {
            let frame = model.envelopeFrame(layout)
            Rectangle()
                .fill(Color.black.opacity(Self.hoverAlpha))
                .frame(width: frame.width, height: frame.height)
                .offset(x: frame.minX, y: frame.minY)
                .accessibilityHidden(true)
        }
    }

    private func plate(_ layout: DockStripLayout) -> some View {
        let frame = model.plateFrame(layout)
        return DockPlate(
            material: model.dock.appearance.material,
            radius: DockPlateShape.plateRadius(tileSize: model.tileSize)
        )
        .frame(width: frame.width, height: frame.height)
        .offset(x: frame.minX, y: frame.minY)
    }

    @ViewBuilder
    private func tiles(_ placed: [Placed], layout: DockStripLayout) -> some View {
        if model.scrolls {
            strip(placed, layout: layout).mask(alignment: .topLeading) {
                Rectangle().frame(width: model.restSize.width, height: model.restSize.height)
            }
        } else {
            strip(placed, layout: layout)
        }
    }

    private func strip(_ placed: [Placed], layout: DockStripLayout) -> some View {
        ZStack(alignment: .topLeading) {
            tileViews(placed)
            handle(layout, after: placed.count)
        }
    }

    /// The grabber at the dock's end, in the last slot of the strip; dragging it moves the dock.
    @ViewBuilder
    private func handle(_ layout: DockStripLayout, after count: Int) -> some View {
        if layout.tiles.indices.contains(count) {
            let frame = model.frame(of: layout.tiles[count])
            let across = model.thickness * Self.handleLengthRatio
            let weight = max(model.tileSize * Self.handleWeightRatio, Self.minimumHandleWeight)
            let vertical = model.edge.isVertical
            Capsule()
                .fill(Theme.Colors.textSecondary)
                .frame(width: vertical ? across : weight, height: vertical ? weight : across)
                .frame(width: frame.width, height: frame.height)
                .offset(x: frame.minX, y: frame.minY)
                .allowsHitTesting(false)
                .accessibilityHidden(true)
        }
    }

    private func tileViews(_ placed: [Placed]) -> some View {
        ForEach(placed) { entry in
            let tile = entry.tile
            let frame = model.frame(of: tile)
            let rest = tile.length / tile.scale
            let render = renderScale(entry.slot, tile: tile, restLength: rest)
            let size = model.edge.isVertical
                ? CGSize(width: model.tileSize * render, height: rest * render)
                : CGSize(width: rest * render, height: model.tileSize * render)
            DockTileView(slot: entry.slot, model: model, size: size, renderScale: render)
                .equatable()
                .frame(width: size.width, height: size.height)
                .scaleEffect(tile.scale / render, anchor: .topLeading)
                .offset(x: frame.minX, y: frame.minY)
                .transition(.scale(scale: 0.5).combined(with: .opacity))
        }
    }

    /// Icons are drawn at their peak and scaled down; a widget only while it grows, so its text is
    /// drawn at rest size the rest of the time rather than shrunk from a larger layout.
    private func renderScale(_ slot: DockSlot, tile: DockStripLayout.Tile, restLength: CGFloat)
        -> CGFloat
    {
        let peak = model.peakScale(restLength: restLength, magnifies: slot.magnifies)
        guard case .pinned(let item, _) = slot, case .widget = item.kind else { return peak }
        return tile.scale > Self.growingScale ? peak : 1
    }

    @ViewBuilder
    private func marker(_ layout: DockStripLayout, slots: [DockSlot]) -> some View {
        if case .insert(let index) = model.drop {
            let pinned = slots.filter { if case .pinned = $0 { true } else { false } }.count
            let frame = model.markerFrame(
                along: layout.insertionAlong(index: index, count: pinned), width: Self.markerWidth)
            Capsule()
                .fill(Theme.Colors.dropGuideArmed)
                .frame(width: frame.width, height: frame.height)
                .offset(x: frame.minX, y: frame.minY)
                .allowsHitTesting(false)
        }
    }
}

/// The dock's backdrop: the material, the panel scrim over it, clipped to the corner, with a
/// shadow that falls only outside the plate so it never shows through the glass.
private struct DockPlate: View {
    let material: DockMaterial
    let radius: CGFloat

    private static let shadowRadius: CGFloat = 10
    private static let shadowOffset: CGFloat = 3
    private static let shadowOpacity = 0.28
    private static let shadowBleed: CGFloat = 40

    var body: some View {
        let shape = RoundedRectangle(cornerRadius: radius, style: .continuous)
        ZStack {
            DockMaterialBackdrop(material: material).id(material)
            // Clear glass is meant to be seen through, so it takes no scrim.
            if material != .glassClear { Theme.Colors.panelScrim }
        }
        .clipShape(shape)
        .overlay(shape.strokeBorder(Theme.Colors.separator, lineWidth: Theme.Size.hairline))
        .background { shadow(shape) }
    }

    private func shadow(_ shape: RoundedRectangle) -> some View {
        shape
            .fill(Color.black)
            .shadow(
                color: .black.opacity(Self.shadowOpacity), radius: Self.shadowRadius,
                y: Self.shadowOffset
            )
            .mask {
                ZStack {
                    Rectangle().padding(-Self.shadowBleed)
                    shape.blendMode(.destinationOut)
                }
                .compositingGroup()
            }
            .allowsHitTesting(false)
    }
}

private struct DockMaterialBackdrop: NSViewRepresentable {
    let material: DockMaterial

    func makeNSView(context: Context) -> NSView {
        switch material {
        case .glassRegular, .glassClear:
            let view = NSGlassEffectView()
            view.style = material == .glassClear ? .clear : .regular
            return view
        case .frosted:
            let view = NSVisualEffectView()
            view.material = .hudWindow
            view.blendingMode = .behindWindow
            view.state = .active
            return view
        }
    }

    func updateNSView(_ nsView: NSView, context: Context) {}
}
