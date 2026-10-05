import Foundation

/// The data sources built-in widgets share across instances; each idles until a tile leases it.
@MainActor
final class DockWidgetServices {
    let clock = DockTimeClock()
    let activity = SystemActivitySampler()
    let battery = SystemBatteryMonitor()
    let network = SystemNetworkSampler()
    let nowPlaying = SystemNowPlayingMonitor()
    let stocks = StockQuoteProvider()

    /// A built-in widget is made with no arguments, so it reaches its services through the owner.
    static var current: DockWidgetServices { AppCore.shared.dockCoordinator.widgets.services }
}
