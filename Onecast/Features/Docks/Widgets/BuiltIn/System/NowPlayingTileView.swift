import AppKit
import OnecastPluginKit
import SwiftUI

struct NowPlayingTileView: View {
    let model: NowPlayingWidgetModel
    let context: DockWidgetContext

    /// A transport button's side, as a fraction of the tile.
    private static let controlFraction: CGFloat = 0.36
    private static let progressFraction: CGFloat = 0.05

    var body: some View {
        let metrics = SystemTileMetrics(context)
        content(metrics)
            .onAppear { model.start() }
            .onDisappear { model.stop() }
    }

    @ViewBuilder
    private func content(_ metrics: SystemTileMetrics) -> some View {
        switch model.content {
        case .hidden:
            Color.clear
        case .loading:
            plate(metrics) { Color.clear }
        case .track(let track, let artwork):
            trackTile(track, artwork: artwork, metrics)
        case .noSources:
            message(
                symbol: "music.note.list", title: "No Source", detail: "Pick a player in settings",
                metrics, action: context.actions.openSettings)
        case .closed(let source):
            message(
                symbol: "music.note", title: "Open", detail: source.title, metrics,
                action: { context.actions.launchApp(source.bundleID) })
        case .stopped(let source):
            message(
                symbol: "music.note", title: "Not Playing", detail: source.title, metrics,
                action: { context.actions.launchApp(source.bundleID) })
        case .denied(let source):
            message(
                symbol: "lock.shield", title: "Allow Access", detail: "Control \(source.title)",
                metrics, action: openAutomationSettings)
        case .failed(let source):
            message(
                symbol: "exclamationmark.triangle", title: "Can't Read", detail: source.title,
                metrics, action: nil)
        }
    }

    private func openAutomationSettings() {
        if let url = SystemNowPlayingMonitor.automationSettingsURL { context.actions.openURL(url) }
    }

    /// Fills the tile; the dock draws the card, so nothing is painted behind the content.
    private func plate<Content: View>(
        _ metrics: SystemTileMetrics, @ViewBuilder content: () -> Content
    ) -> some View {
        content().frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private func message(
        symbol: String, title: String, detail: String, _ metrics: SystemTileMetrics,
        action: (@MainActor () -> Void)?
    ) -> some View {
        let layout = metrics.isVertical || metrics.isCompact
            ? AnyLayout(VStackLayout(spacing: metrics.spacing))
            : AnyLayout(HStackLayout(spacing: metrics.spacing))
        let surface = plate(metrics) {
            layout {
                SymbolImage(name: symbol, size: metrics.symbolSize(metrics.isCompact ? 0.3 : 0.36))
                    .foregroundStyle(Theme.Colors.textPrimary)
                VStack(alignment: metrics.isCompact || metrics.isVertical ? .center : .leading, spacing: 0) {
                    Text(title)
                        .font(metrics.font(metrics.isCompact ? .caption : .label))
                        .foregroundStyle(Theme.Colors.textPrimary)
                    if !metrics.isCompact {
                        Text(detail)
                            .font(metrics.font(.caption, weight: .medium))
                            .foregroundStyle(Theme.Colors.textSecondary)
                    }
                }
                .lineLimit(1)
                .minimumScaleFactor(0.6)
            }
            .padding(metrics.padding)
        }
        return Group {
            if let action {
                Button(action: action) { surface.contentShape(Rectangle()) }
                    .buttonStyle(.plain)
                    .onHover { model.isPointerOnControl = $0 }
            } else {
                surface
            }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("\(title), \(detail)")
    }

    private func trackTile(
        _ track: SystemNowPlaying.Track, artwork: NSImage?, _ metrics: SystemTileMetrics
    ) -> some View {
        GeometryReader { proxy in
            let settings = model.settings
            let vertical = metrics.isVertical
            let layout = SystemNowPlaying.TileLayout.resolve(
                length: vertical ? proxy.size.height : proxy.size.width,
                thickness: vertical ? proxy.size.width : proxy.size.height, isVertical: vertical,
                settings: settings, inset: metrics.padding,
                control: metrics.tileLength * Self.controlFraction)
            plate(metrics) {
                arrangement(track, artwork: artwork, layout, metrics)
            }
        }
        .accessibilityElement(children: .contain)
    }

    @ViewBuilder
    private func arrangement(
        _ track: SystemNowPlaying.Track, artwork: NSImage?, _ layout: SystemNowPlaying.TileLayout,
        _ metrics: SystemTileMetrics
    ) -> some View {
        if !layout.showsText && layout.controls.isEmpty {
            artworkOnly(track, artwork: artwork, layout, metrics)
        } else {
            let stack = metrics.isVertical
                ? AnyLayout(VStackLayout(spacing: metrics.padding))
                : AnyLayout(HStackLayout(spacing: metrics.padding))
            stack {
                if layout.artworkTogglesPlayback {
                    NowPlayingArtworkToggle(
                        image: artwork, side: layout.artworkSide, isPlaying: track.isPlaying,
                        onHover: { model.isPointerOnControl = $0 }
                    ) {
                        model.perform(.playPause, on: track.source)
                    }
                } else {
                    NowPlayingArtworkView(image: artwork, side: layout.artworkSide)
                }
                if layout.showsText { textBlock(track, layout, metrics) }
                if !layout.controls.isEmpty { controlRow(track, layout, metrics) }
            }
            .padding(metrics.padding)
        }
    }

    private func artworkOnly(
        _ track: SystemNowPlaying.Track, artwork: NSImage?, _ layout: SystemNowPlaying.TileLayout,
        _ metrics: SystemTileMetrics
    ) -> some View {
        ZStack {
            NowPlayingArtworkView(image: artwork, side: layout.artworkSide)
            if !track.isPlaying {
                RoundedRectangle(cornerRadius: layout.artworkSide * 0.2, style: .continuous)
                    .fill(Theme.Colors.panelScrim)
                    .frame(width: layout.artworkSide, height: layout.artworkSide)
                SymbolImage(name: "pause.fill", size: layout.artworkSide * 0.35)
                    .foregroundStyle(Theme.Colors.textPrimary)
            }
            if layout.showsProgress {
                VStack {
                    Spacer(minLength: 0)
                    SystemMeterBar(
                        fraction: track.progress, tint: Theme.Colors.textPrimary,
                        height: metrics.tileLength * Self.progressFraction)
                }
                .padding(metrics.spacing)
                .frame(width: layout.artworkSide, height: layout.artworkSide)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(accessibilityLabel(track))
    }

    private func textBlock(
        _ track: SystemNowPlaying.Track, _ layout: SystemNowPlaying.TileLayout,
        _ metrics: SystemTileMetrics
    ) -> some View {
        VStack(alignment: .leading, spacing: metrics.spacing) {
            Text(track.title.isEmpty ? track.source.title : track.title)
                .font(metrics.font(.label))
                .foregroundStyle(Theme.Colors.textPrimary)
                .lineLimit(1)
            if !track.artist.isEmpty {
                Text(track.artist)
                    .font(metrics.font(.caption, weight: .medium))
                    .foregroundStyle(Theme.Colors.textSecondary)
                    .lineLimit(1)
            }
            if layout.showsProgress {
                SystemMeterBar(
                    fraction: track.progress, tint: Theme.Colors.textPrimary,
                    height: metrics.tileLength * Self.progressFraction)
            }
        }
        .frame(
            maxWidth: .infinity, maxHeight: metrics.isVertical ? .infinity : nil, alignment: .topLeading
        )
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(accessibilityLabel(track))
    }

    private func controlRow(
        _ track: SystemNowPlaying.Track, _ layout: SystemNowPlaying.TileLayout,
        _ metrics: SystemTileMetrics
    ) -> some View {
        HStack(spacing: metrics.padding) {
            ForEach(layout.controls, id: \.self) { control in
                NowPlayingControlButton(
                    control: control, isPlaying: track.isPlaying, skipSeconds: model.settings.skipSeconds,
                    size: metrics.tileLength * Self.controlFraction,
                    onHover: { model.isPointerOnControl = $0 }
                ) {
                    model.perform(control, on: track.source)
                }
            }
        }
    }

    private func accessibilityLabel(_ track: SystemNowPlaying.Track) -> String {
        let state = track.isPlaying ? "Playing" : "Paused"
        return [state, track.title, track.artist].filter { !$0.isEmpty }.joined(separator: ", ")
    }
}
