import OnecastPluginKit
import SwiftUI

/// Spotify and Apple Music playback, read and controlled through Apple Events.
final class NowPlayingWidget: OnecastDockWidget {
    static var metadata: DockWidgetMetadata {
        DockWidgetMetadata(
            name: "Now Playing", subtitle: "Spotify and Apple Music, with controls",
            icon: "play.circle", category: "System", sizes: [.wide, .compact, .expanded])
    }

    static let preferences = [
        PluginPreference(
            name: SystemNowPlaying.Settings.Name.spotify, title: "Spotify", kind: .checkbox,
            defaultValue: .bool(true)),
        PluginPreference(
            name: SystemNowPlaying.Settings.Name.music, title: "Apple Music", kind: .checkbox,
            defaultValue: .bool(true)),
        PluginPreference(
            name: SystemNowPlaying.Settings.Name.layout, title: "Layout", kind: .dropdown,
            options: [
                PluginPreference.Option(title: "Mini", value: "mini"),
                PluginPreference.Option(title: "Full", value: "full"),
            ], defaultValue: .string("mini")),
        PluginPreference(
            name: SystemNowPlaying.Settings.Name.showsPreviousNext, title: "Show previous and next",
            kind: .checkbox, defaultValue: .bool(true)),
        PluginPreference(
            name: SystemNowPlaying.Settings.Name.skipSeconds, title: "Skip interval", kind: .dropdown,
            options: SystemNowPlaying.Settings.skipOptions.map {
                PluginPreference.Option(title: $0 == 0 ? "Off" : "\($0) seconds", value: String($0))
            }, defaultValue: .string("0")),
        PluginPreference(
            name: SystemNowPlaying.Settings.Name.hidesWhenClosed, title: "Hide when music apps are closed",
            kind: .checkbox, defaultValue: .bool(false)),
    ]

    private let model = NowPlayingWidgetModel()

    required init() {}

    func tile(context: DockWidgetContext) -> AnyView {
        model.configure(instanceID: context.instanceID)
        return AnyView(NowPlayingTileView(model: model, context: context))
    }

    func popover(context: DockWidgetContext) -> AnyView? {
        guard !model.isPointerOnControl else { return nil }
        model.configure(instanceID: context.instanceID)
        return AnyView(NowPlayingPopoverView(model: model, context: context))
    }

    func didRemove() {
        model.stop()
    }
}
