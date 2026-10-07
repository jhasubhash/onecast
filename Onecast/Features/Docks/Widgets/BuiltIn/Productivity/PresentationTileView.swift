import OnecastPluginKit
import SwiftUI

/// Compact shows the state; wide adds the toggle; expanded adds what is shown and a re-fit.
struct PresentationTileView: View {
    let context: DockWidgetContext
    let onPhaseChange: () -> Void
    let onControlHover: (Bool) -> Void

    private static let buttonFraction: CGFloat = 0.6
    private static let iconFraction: CGFloat = 0.2

    private var coordinator: PresentationCoordinator { AppCore.shared.presentationCoordinator }
    private var settings: AppSettings { AppCore.shared.settings }

    var body: some View {
        ProductivityTile(context: context) { geometry in
            TimeLiveView(granularity: .second) { now in
                content(geometry, PresentationDockReading(coordinator, now: now))
            }
        }
        .onChange(of: coordinator.phase) { onPhaseChange() }
    }

    @ViewBuilder
    private func content(
        _ geometry: ProductivityTileGeometry, _ reading: PresentationDockReading
    ) -> some View {
        switch geometry.span {
        case .compact:
            face(geometry, reading)
        case .wide:
            axis(geometry) {
                face(geometry, reading)
                toggle(geometry, reading)
            }
        case .expanded:
            axis(geometry) {
                face(geometry, reading)
                    .frame(width: geometry.isVertical ? nil : geometry.unit)
                details(geometry, reading)
                if reading.isPresenting {
                    PresentationTileButton(
                        symbol: "arrow.up.left.and.arrow.down.right", ink: Theme.Colors.textPrimary,
                        size: geometry.unit * Self.buttonFraction, label: "Re-fit Window",
                        onHover: onControlHover, action: coordinator.refit)
                }
                toggle(geometry, reading)
            }
        }
    }

    private func axis<Content: View>(
        _ geometry: ProductivityTileGeometry, @ViewBuilder content: () -> Content
    ) -> some View {
        Group {
            if geometry.isVertical {
                VStack(spacing: geometry.gap) { content() }
            } else {
                HStack(spacing: geometry.gap) { content() }
            }
        }
    }

    private func face(
        _ geometry: ProductivityTileGeometry, _ reading: PresentationDockReading
    ) -> some View {
        ProductivityTileFace(
            geometry: geometry, color: reading.tint, label: reading.label, caption: reading.caption,
            captionLines: 1
        ) {
            SymbolImage(name: PresentationDockWidget.symbol, size: geometry.pointSize(0.3))
                .foregroundStyle(reading.isPresenting ? reading.tint : Theme.Colors.textPrimary)
        }
    }

    private func toggle(
        _ geometry: ProductivityTileGeometry, _ reading: PresentationDockReading
    ) -> some View {
        PresentationTileButton(
            symbol: reading.toggleSymbol,
            ink: reading.isPresenting ? Theme.Colors.destructive : Theme.Colors.textPrimary,
            size: geometry.unit * Self.buttonFraction, label: reading.toggleTitle,
            onHover: onControlHover, action: coordinator.toggle
        )
        .disabled(reading.isBusy || !settings.presentationEnabled)
    }

    private func details(
        _ geometry: ProductivityTileGeometry, _ reading: PresentationDockReading
    ) -> some View {
        VStack(alignment: .leading, spacing: geometry.gap) {
            HStack(spacing: geometry.gap) {
                if let icon = reading.appIcon {
                    Image(nsImage: icon)
                        .resizable()
                        .frame(
                            width: geometry.unit * Self.iconFraction,
                            height: geometry.unit * Self.iconFraction)
                }
                Text(reading.appName ?? (reading.isPresenting ? "Switch to an app" : "Not presenting"))
                    .font(geometry.font(0.17, weight: .semibold))
                    .foregroundStyle(Theme.Colors.textPrimary)
            }
            Text(reading.isPresenting ? reading.resolution : resolutionPlan)
                .font(geometry.font(0.14))
                .foregroundStyle(Theme.Colors.textSecondary)
            Text(windowPlan)
                .font(geometry.font(0.14))
                .foregroundStyle(Theme.Colors.textSecondary)
        }
        .lineLimit(1)
        .minimumScaleFactor(0.7)
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var windowPlan: String {
        let size = settings.presentationWindowSize
        return size == .margin ? "\(size.shortTitle) \(settings.presentationMarginPercent)%" : size.shortTitle
    }

    private var resolutionPlan: String {
        settings.presentationResolutions.isEmpty ? "Resolution unchanged" : "Resolution set"
    }
}

/// A quiet circle with one glyph, lifting on hover; no tooltip, which the dock's window would clip.
private struct PresentationTileButton: View {
    let symbol: String
    let ink: Color
    let size: CGFloat
    let label: String
    let onHover: (Bool) -> Void
    let action: () -> Void
    @State private var hovered = false

    private static let glyphFraction: CGFloat = 0.42

    var body: some View {
        Button(action: action) {
            SymbolImage(name: symbol, size: size * Self.glyphFraction)
                .foregroundStyle(ink)
                .frame(width: size, height: size)
                .background(
                    Circle().fill(hovered ? Theme.Colors.controlHover : Theme.Colors.controlSurface))
                .contentShape(Circle())
        }
        .buttonStyle(ProductivityPressStyle())
        .onHover { hovering in
            hovered = hovering
            onHover(hovering)
        }
        .accessibilityLabel(label)
    }
}
