import AppKit
import OnecastPluginKit
import SwiftUI

/// A built-in widget that takes files and links dropped on its tile; the dock routes the drop.
@MainActor
protocol DockFileReceiving: AnyObject {
    /// True when the widget took the drop.
    func receive(_ urls: [URL]) -> Bool
}

/// A drop target that hands files and links to the system's AirDrop picker.
@MainActor
final class AirDropDockWidget: OnecastDockWidget, DockFileReceiving {
    static let metadata = DockWidgetMetadata(
        name: "AirDrop", subtitle: "Drop files here to send them to a nearby device",
        icon: "dot.radiowaves.up.forward", category: "Productivity", sizes: [.compact, .wide])

    private let model = AirDropModel()

    func tile(context: DockWidgetContext) -> AnyView {
        AnyView(AirDropDockTile(context: context, model: model))
    }

    func popover(context: DockWidgetContext) -> AnyView? {
        AnyView(AirDropPopover(context: context, model: model))
    }

    func receive(_ urls: [URL]) -> Bool {
        guard !urls.isEmpty else { return false }
        model.send(urls)
        return true
    }
}

/// Reports a share's outcome; a dismissed picker is the reader's choice, not a failure.
@MainActor
private final class AirDropSession: NSObject, NSSharingServiceDelegate {
    var onFailure: (@MainActor (Error) -> Void)?

    func sharingService(_ sharingService: NSSharingService, didFailToShareItems items: [Any], error: Error) {
        guard (error as NSError).code != NSUserCancelledError else { return }
        onFailure?(error)
    }
}

@MainActor
@Observable
final class AirDropModel {
    /// The real AirDrop icon, which the sharing service vends at 256pt; nil when AirDrop is absent.
    let icon: NSImage? = NSSharingService(named: .sendViaAirDrop)?.image

    var isAvailable: Bool { icon != nil }

    @ObservationIgnored private let session = AirDropSession()
    /// Held until the picker closes, or AppKit drops the share with it.
    @ObservationIgnored private var service: NSSharingService?

    init() {
        session.onFailure = { error in
            AppCore.shared.showMessage(
                "AirDrop failed: \(error.localizedDescription)", tone: .danger)
        }
    }

    func send(_ urls: [URL]) {
        guard !urls.isEmpty else { return }
        guard let service = NSSharingService(named: .sendViaAirDrop),
            service.canPerform(withItems: urls)
        else {
            AppCore.shared.showMessage("AirDrop isn't available right now", tone: .danger)
            return
        }
        service.delegate = session
        self.service = service
        NSApp.activate()
        service.perform(withItems: urls)
    }

    /// Onecast is an accessory app, so the panel needs the app active to open in front.
    func chooseFiles() {
        let panel = NSOpenPanel()
        panel.canChooseFiles = true
        panel.canChooseDirectories = true
        panel.allowsMultipleSelection = true
        panel.prompt = "Send"
        panel.message = "Choose what to send with AirDrop"
        NSApp.activate()
        guard panel.runModal() == .OK else { return }
        send(panel.urls)
    }
}

// MARK: - Tile

struct AirDropDockTile: View {
    let context: DockWidgetContext
    let model: AirDropModel

    var body: some View {
        ProductivityTile(context: context) { geometry in
            ProductivityTileFace(
                geometry: geometry, color: Theme.Colors.dropGuideArmed, label: "AirDrop",
                caption: "Drop files to send"
            ) {
                glyph(geometry)
            }
        }
        .accessibilityLabel("AirDrop")
    }

    @ViewBuilder
    private func glyph(_ geometry: ProductivityTileGeometry) -> some View {
        if let icon = model.icon {
            Image(nsImage: icon)
                .resizable()
                .scaledToFit()
                .frame(width: geometry.unit * 0.36, height: geometry.unit * 0.36)
        } else {
            SymbolImage(name: "dot.radiowaves.up.forward", size: geometry.pointSize(0.34))
                .foregroundStyle(Theme.Colors.textTertiary)
        }
    }
}

// MARK: - Popover

struct AirDropPopover: View {
    let context: DockWidgetContext
    let model: AirDropModel

    var body: some View {
        ProductivityPopover {
            ProductivityPopoverHeader(title: "AirDrop", subtitle: "Send to a nearby device")
            if model.isAvailable {
                Text("Drop files or links on the tile, or choose files to send.")
                    .font(Theme.Typography.rowTrailing)
                    .foregroundStyle(Theme.Colors.textSecondary)
                    .fixedSize(horizontal: false, vertical: true)
                ProductivityPill(title: "Choose Files…", symbol: "folder.badge.plus", isProminent: true) {
                    context.actions.closePopover()
                    model.chooseFiles()
                }
            } else {
                ProductivityPopoverMessage(
                    symbol: "exclamationmark.triangle", text: "AirDrop isn't available on this Mac.")
            }
        }
    }
}
