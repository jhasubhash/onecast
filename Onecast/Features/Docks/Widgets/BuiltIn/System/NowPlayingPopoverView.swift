import AppKit
import OnecastPluginKit
import SwiftUI

struct NowPlayingPopoverView: View {
    let model: NowPlayingWidgetModel
    let context: DockWidgetContext

    private static let artworkSide: CGFloat = 200
    private static let controlSide = Theme.Size.menuButton

    var body: some View {
        VStack(spacing: Theme.Spacing.xl) {
            switch model.content {
            case .track(let track, let artwork): trackBody(track, artwork: artwork)
            case .denied(let source): deniedBody(source)
            case .stopped(let source): idleBody(source, message: "Nothing is playing in \(source.title).")
            case .closed(let source): idleBody(source, message: "\(source.title) is not open.")
            case .failed(let source): idleBody(source, message: "\(source.title) did not answer.", launches: false)
            case .noSources:
                note("Choose Spotify or Music in this widget's settings.")
                BarButton(chrome: .rounded, action: context.actions.openSettings) { label("Open Settings…") }
            case .loading, .hidden:
                note("Looking for Spotify and Music…")
            }
        }
        .padding(SystemPopover.padding)
        .frame(width: SystemPopover.width)
    }

    private func trackBody(_ track: SystemNowPlaying.Track, artwork: NSImage?) -> some View {
        VStack(spacing: Theme.Spacing.xl) {
            NowPlayingArtworkView(image: artwork, side: Self.artworkSide)
            VStack(spacing: Theme.Spacing.xxs) {
                Text(track.title.isEmpty ? track.source.title : track.title)
                    .font(Theme.Typography.panelTitle)
                    .foregroundStyle(Theme.Colors.textPrimary)
                    .lineLimit(2)
                if !track.artist.isEmpty {
                    Text(track.artist)
                        .font(Theme.Typography.rowTrailing)
                        .foregroundStyle(Theme.Colors.textSecondary)
                        .lineLimit(1)
                }
                if !track.album.isEmpty {
                    Text(track.album)
                        .font(Theme.Typography.keyCap)
                        .foregroundStyle(Theme.Colors.textTertiary)
                        .lineLimit(1)
                }
            }
            .multilineTextAlignment(.center)
            .accessibilityElement(children: .combine)
            progress(track)
            controls(track)
            BarButton(chrome: .rounded, action: { context.actions.launchApp(track.source.bundleID) }) {
                label("Open \(track.source.title)")
            }
        }
    }

    @ViewBuilder
    private func progress(_ track: SystemNowPlaying.Track) -> some View {
        if track.duration > 0 {
            VStack(spacing: Theme.Spacing.xs) {
                SystemMeterBar(fraction: track.progress, tint: Theme.Colors.textPrimary)
                HStack {
                    Text(SystemFormat.clock(seconds: track.position))
                    Spacer()
                    Text("-\(SystemFormat.clock(seconds: track.duration - track.position))")
                }
                .font(Theme.Typography.keyCap.monospacedDigit())
                .foregroundStyle(Theme.Colors.textTertiary)
            }
            .accessibilityElement(children: .ignore)
            .accessibilityLabel("Progress")
            .accessibilityValue(
                "\(SystemFormat.clock(seconds: track.position)) of \(SystemFormat.clock(seconds: track.duration))")
        }
    }

    private func controls(_ track: SystemNowPlaying.Track) -> some View {
        let settings = model.settings
        var shown: [SystemNowPlaying.Control] = [.playPause]
        if settings.showsPreviousNext { shown += [.previous, .next] }
        if settings.skipsEnabled { shown += [.skipBack, .skipForward] }
        return HStack(spacing: Theme.Spacing.md) {
            ForEach(SystemNowPlaying.Control.allCases.filter(shown.contains), id: \.self) { control in
                NowPlayingControlButton(
                    control: control, isPlaying: track.isPlaying, skipSeconds: settings.skipSeconds,
                    size: Self.controlSide
                ) {
                    model.perform(control, on: track.source)
                }
            }
        }
    }

    @ViewBuilder
    private func deniedBody(_ source: SystemNowPlaying.Source) -> some View {
        SymbolImage(name: "lock.shield", size: Theme.Size.dialogIcon)
            .foregroundStyle(Theme.Colors.textPrimary)
        note(
            "Onecast needs permission to control \(source.title). Allow it under Privacy & Security › Automation, then come back."
        )
        if let url = SystemNowPlayingMonitor.automationSettingsURL {
            BarButton(chrome: .rounded, action: { context.actions.openURL(url) }) {
                label("Open Automation Settings…")
            }
        }
    }

    @ViewBuilder
    private func idleBody(
        _ source: SystemNowPlaying.Source, message: String, launches: Bool = true
    ) -> some View {
        SymbolImage(name: "music.note", size: Theme.Size.dialogIcon)
            .foregroundStyle(Theme.Colors.textPrimary)
        note(message)
        if launches {
            BarButton(chrome: .rounded, action: { context.actions.launchApp(source.bundleID) }) {
                label("Open \(source.title)")
            }
        }
    }

    private func note(_ text: String) -> some View {
        Text(text)
            .font(Theme.Typography.rowTrailing)
            .foregroundStyle(Theme.Colors.textSecondary)
            .multilineTextAlignment(.center)
            .fixedSize(horizontal: false, vertical: true)
    }

    private func label(_ title: String) -> some View {
        Text(title)
            .font(Theme.Typography.bar)
            .foregroundStyle(Theme.Colors.textPrimary)
    }
}
