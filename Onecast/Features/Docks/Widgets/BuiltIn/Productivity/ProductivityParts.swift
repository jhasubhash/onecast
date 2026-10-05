import AppKit
import OnecastPluginKit
import SwiftUI

/// Lengths shared by the Productivity widgets' popovers; a tile's own sizes follow its slot.
enum DockProductivityMetrics {
    static let popoverWidth: CGFloat = 320
    static let popoverListMaxHeight: CGFloat = 320
    static let rowIcon: CGFloat = 18
    static let rowHeight: CGFloat = 36
    static let calendarBarWidth: CGFloat = 3
    static let calendarBarHeight: CGFloat = 28
    static let messageGlyph: CGFloat = 26
}

/// The slot a tile is drawn in, so one layout serves a 24pt dock and a 128pt one alike.
struct ProductivityTileGeometry {
    private static let minimumFontSize: CGFloat = 8

    let size: CGSize
    let span: DockWidgetSize
    let isVertical: Bool

    /// The dock's tile length: a compact slot is this square, a longer one this across.
    var unit: CGFloat { min(size.width, size.height) }
    var inset: CGFloat { unit * 0.1 }
    var gap: CGFloat { unit * 0.06 }
    var dotSize: CGFloat { max(4, unit * 0.09) }
    var isCompact: Bool { span == .compact }
    var contentSize: CGSize {
        CGSize(width: max(0, size.width - 2 * inset), height: max(0, size.height - 2 * inset))
    }

    /// Text scales with the tile: a dock's tiles run 24–128pt, which no text style spans.
    func font(_ ratio: CGFloat, weight: Font.Weight = .regular, design: Font.Design = .default) -> Font {
        .system(size: pointSize(ratio), weight: weight, design: design)
    }

    func pointSize(_ ratio: CGFloat) -> CGFloat {
        max(Self.minimumFontSize, unit * ratio)
    }

    /// Whole lines of `ratio`-sized text that fit in `height`, never fewer than one.
    func lines(of ratio: CGFloat, in height: CGFloat) -> Int {
        max(1, Int(height / (pointSize(ratio) * 1.3)))
    }

    /// A panel under this much room stacks its text instead of laying it out in a row.
    func isNarrow(_ panel: CGSize) -> Bool { panel.width < unit * 1.5 }
}

/// Every Productivity tile's frame: the slot's content area, since the dock draws the card itself.
struct ProductivityTile<Content: View>: View {
    let context: DockWidgetContext
    @ViewBuilder let content: (ProductivityTileGeometry) -> Content

    var body: some View {
        GeometryReader { proxy in
            let geometry = ProductivityTileGeometry(
                size: proxy.size, span: context.size, isVertical: context.edge.isVertical)
            content(geometry)
                .padding(geometry.inset)
                .frame(width: proxy.size.width, height: proxy.size.height)
        }
    }
}

/// A small accent dot and a short secondary label, ending in an ellipsis when it cannot fit.
struct ProductivityTileHeader: View {
    let geometry: ProductivityTileGeometry
    let color: Color
    let label: String

    var body: some View {
        HStack(spacing: geometry.gap) {
            Circle()
                .fill(color)
                .frame(width: geometry.dotSize, height: geometry.dotSize)
            Text(label)
                .font(geometry.font(0.15, weight: .medium))
                .foregroundStyle(Theme.Colors.textSecondary)
                .lineLimit(1)
                .truncationMode(.tail)
        }
        .frame(maxWidth: .infinity)
        .accessibilityElement(children: .combine)
    }
}

/// The large, bold primary value of a tile.
struct ProductivityValueText: View {
    let geometry: ProductivityTileGeometry
    let text: String
    var ratio: CGFloat = 0.3
    var lines = 1

    var body: some View {
        Text(text)
            .font(geometry.font(ratio, weight: .bold))
            .foregroundStyle(Theme.Colors.textPrimary)
            .multilineTextAlignment(.center)
            .lineLimit(lines)
            .minimumScaleFactor(0.5)
    }
}

/// Header, value and caption, centered: the face every Productivity tile wears.
struct ProductivityTileFace<Value: View, Footer: View>: View {
    let geometry: ProductivityTileGeometry
    let color: Color
    let label: String
    let caption: String?
    let captionColor: Color
    let captionLines: Int
    let value: Value
    let footer: Footer

    init(
        geometry: ProductivityTileGeometry, color: Color, label: String, caption: String? = nil,
        captionColor: Color = Theme.Colors.textSecondary, captionLines: Int = 2,
        @ViewBuilder value: () -> Value, @ViewBuilder footer: () -> Footer
    ) {
        self.geometry = geometry
        self.color = color
        self.label = label
        self.caption = caption
        self.captionColor = captionColor
        self.captionLines = captionLines
        self.value = value()
        self.footer = footer()
    }

    var body: some View {
        ViewThatFits(in: .vertical) {
            stack(showsCaption: true, showsFooter: true)
            stack(showsCaption: true, showsFooter: false)
            stack(showsCaption: false, showsFooter: false)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    /// Whatever the slot is too short for is dropped, footer first, never overflowed.
    private func stack(showsCaption: Bool, showsFooter: Bool) -> some View {
        VStack(spacing: geometry.gap) {
            ProductivityTileHeader(geometry: geometry, color: color, label: label)
            Spacer(minLength: 0)
            value
            if showsCaption, let caption {
                Text(caption)
                    .font(geometry.font(0.14))
                    .foregroundStyle(captionColor)
                    .multilineTextAlignment(.center)
                    .lineLimit(captionLines)
                    .minimumScaleFactor(0.8)
            }
            Spacer(minLength: 0)
            if showsFooter { footer }
        }
    }
}

extension ProductivityTileFace where Footer == EmptyView {
    init(
        geometry: ProductivityTileGeometry, color: Color, label: String, caption: String? = nil,
        captionColor: Color = Theme.Colors.textSecondary, captionLines: Int = 2,
        @ViewBuilder value: () -> Value
    ) {
        self.init(
            geometry: geometry, color: color, label: label, caption: caption,
            captionColor: captionColor, captionLines: captionLines, value: value
        ) { EmptyView() }
    }
}

/// A tile's one call to action, for a permission the widget cannot work without.
struct ProductivityAccessPrompt: View {
    let geometry: ProductivityTileGeometry
    let color: Color
    let label: String
    let symbol: String
    let title: String
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            ProductivityTileFace(
                geometry: geometry, color: color, label: label, caption: title,
                captionColor: Theme.Colors.textPrimary
            ) {
                SymbolImage(name: symbol, size: geometry.pointSize(0.3))
                    .foregroundStyle(Theme.Colors.textSecondary)
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(ProductivityPressStyle())
        .accessibilityLabel(title)
    }
}

/// Dims a button while it is held, so a plain-styled control still answers the pointer.
struct ProductivityPressStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label.opacity(configuration.isPressed ? 0.55 : 1)
    }
}

/// A popover's frame: the fixed width every Productivity popover shares, and its padding.
struct ProductivityPopover<Content: View>: View {
    @ViewBuilder let content: Content

    var body: some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.lg) {
            content
        }
        .padding(Theme.Spacing.xl)
        .frame(width: DockProductivityMetrics.popoverWidth, alignment: .leading)
    }
}

/// A popover's title row, with the one action that opens the widget's own app.
struct ProductivityPopoverHeader: View {
    let title: String
    var subtitle: String?
    var actionTitle: String?
    var actionSymbol = "arrow.up.forward.app"
    var action: (() -> Void)?

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: Theme.Spacing.md) {
            VStack(alignment: .leading, spacing: Theme.Spacing.xxs) {
                Text(title)
                    .font(Theme.Typography.panelTitle)
                    .foregroundStyle(Theme.Colors.textPrimary)
                    .lineLimit(1)
                if let subtitle {
                    Text(subtitle)
                        .font(Theme.Typography.rowTrailing)
                        .foregroundStyle(Theme.Colors.textSecondary)
                        .lineLimit(1)
                }
            }
            Spacer(minLength: Theme.Spacing.md)
            if let actionTitle, let action {
                ProductivityPill(title: actionTitle, symbol: actionSymbol, action: action)
            }
        }
    }
}

/// A small capsule button; the prominent one is the thing the popover is mostly for.
struct ProductivityPill: View {
    let title: String
    var symbol: String?
    var isProminent = false
    let action: () -> Void
    @State private var hovered = false

    var body: some View {
        Button(action: action) {
            HStack(spacing: Theme.Spacing.xs) {
                if let symbol { SymbolImage(name: symbol, size: Theme.Typography.menuSymbolSize) }
                Text(title)
                    .font(Theme.Typography.bar)
                    .lineLimit(1)
            }
            .foregroundStyle(isProminent ? Color.white : Theme.Colors.textPrimary)
            .padding(.horizontal, Theme.Spacing.lg)
            .frame(height: Theme.Size.barButtonHeight)
            .background(Capsule().fill(fill))
            .contentShape(Capsule())
        }
        .buttonStyle(ProductivityPressStyle())
        .onHover { hovered = $0 }
        .animation(.easeOut(duration: Theme.Duration.hover), value: hovered)
    }

    private var fill: Color {
        if isProminent { return Color.accentColor.opacity(hovered ? 0.85 : 1) }
        return hovered ? Theme.Colors.controlHover : Theme.Colors.controlSurface
    }
}

/// A list row that lifts under the pointer; the whole row is the hit area.
struct ProductivityRowButton<Label: View>: View {
    let action: () -> Void
    @ViewBuilder let label: Label
    @State private var hovered = false

    var body: some View {
        Button(action: action) {
            label
                .padding(.horizontal, Theme.Spacing.md)
                .padding(.vertical, Theme.Spacing.sm)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(
                    RoundedRectangle(cornerRadius: Theme.Radius.menuRow, style: .continuous)
                        .fill(hovered ? Theme.Colors.menuHover : Color.clear)
                )
                .contentShape(RoundedRectangle(cornerRadius: Theme.Radius.menuRow, style: .continuous))
        }
        .buttonStyle(.plain)
        .onHover { hovered = $0 }
    }
}

/// A single-line field on a control surface, the popovers' one text-entry look.
struct ProductivityField: View {
    let prompt: String
    @Binding var text: String
    var symbol: String?
    var onSubmit: () -> Void = {}

    var body: some View {
        HStack(spacing: Theme.Spacing.md) {
            if let symbol {
                SymbolImage(name: symbol, size: Theme.Typography.menuSymbolSize)
                    .foregroundStyle(Theme.Colors.textSecondary)
            }
            TextField(prompt, text: $text)
                .textFieldStyle(.plain)
                .font(Theme.Typography.rowTitle)
                .foregroundStyle(Theme.Colors.textPrimary)
                .onSubmit(onSubmit)
        }
        .padding(.horizontal, Theme.Spacing.lg)
        .frame(height: Theme.Size.barButtonHeight + Theme.Spacing.md)
        .background(
            RoundedRectangle(cornerRadius: Theme.Radius.barControl, style: .continuous)
                .fill(Theme.Colors.controlSurface)
        )
    }
}

/// A popover's empty or blocked state: one glyph and a sentence, with room for a button.
struct ProductivityPopoverMessage<Actions: View>: View {
    let symbol: String
    let text: String
    @ViewBuilder let actions: Actions

    var body: some View {
        VStack(spacing: Theme.Spacing.lg) {
            SymbolImage(name: symbol, size: DockProductivityMetrics.messageGlyph)
                .foregroundStyle(Theme.Colors.textTertiary)
            Text(text)
                .font(Theme.Typography.rowTrailing)
                .foregroundStyle(Theme.Colors.textSecondary)
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)
            actions
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, Theme.Spacing.xl)
    }
}

extension ProductivityPopoverMessage where Actions == EmptyView {
    init(symbol: String, text: String) {
        self.init(symbol: symbol, text: text) { EmptyView() }
    }
}
