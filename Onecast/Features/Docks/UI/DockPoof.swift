import AppKit
import SwiftUI

/// A puff where a tile was dragged off its dock and removed.
@MainActor
enum DockPoof {
    private static let duration: TimeInterval = 0.35
    private static let reach: CGFloat = 1.8

    static func show(image: NSImage, atScreen point: CGPoint) {
        guard !NSWorkspace.shared.accessibilityDisplayShouldReduceMotion else { return }
        let panel = HUDPanel(acceptsMouseEvents: false)
        panel.level = .popUpMenu
        panel.hasShadow = false
        let side = max(image.size.width, image.size.height) * reach
        panel.setFrame(
            CGRect(x: point.x - side / 2, y: point.y - side / 2, width: side, height: side),
            display: false)
        let host = NSHostingView(rootView: DockPoofView(image: image, reach: reach))
        host.sizingOptions = []
        panel.contentView = host
        panel.orderFrontRegardless()
        Task {
            try? await Task.sleep(for: .seconds(duration + 0.1))
            panel.orderOut(nil)
            panel.close()
        }
    }
}

private struct DockPoofView: View {
    let image: NSImage
    let reach: CGFloat
    @State private var gone = false

    var body: some View {
        Image(nsImage: image)
            .resizable()
            .scaledToFit()
            .scaleEffect(gone ? reach : 1)
            .opacity(gone ? 0 : 1)
            .blur(radius: gone ? 8 : 0)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .onAppear { withAnimation(.easeOut(duration: 0.35)) { gone = true } }
    }
}
