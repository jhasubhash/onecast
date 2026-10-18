import AppKit
import SwiftUI

/// Draws the shelf's hover labels in a panel of their own, since the shelf's small window would clip them.
@MainActor
final class ShelfTooltip {
    private var panel: NSPanel?
    private var owner: UUID?

    private static let gap: CGFloat = 6

    func presenter(in hosting: NSView) -> TooltipPresenter {
        TooltipPresenter(
            show: { [weak self, weak hosting] owner, text, frame in
                guard let self, let hosting, let window = hosting.window else { return }
                show(text, owner: owner, above: window.convertToScreen(hosting.convert(frame, to: nil)))
            },
            hide: { [weak self] owner in self?.hide(owner: owner) })
    }

    func hide(owner: UUID? = nil) {
        guard owner == nil || owner == self.owner else { return }
        panel?.orderOut(nil)
        self.owner = nil
    }

    private func show(_ text: String, owner: UUID, above anchor: NSRect) {
        let hosting = NSHostingView(rootView: TooltipChip(text: text))
        hosting.setFrameSize(hosting.fittingSize)
        let panel = self.panel ?? Self.makePanel()
        self.panel = panel
        self.owner = owner
        panel.contentView = hosting
        let size = hosting.fittingSize
        var origin = NSPoint(x: anchor.midX - size.width / 2, y: anchor.maxY + Self.gap)
        if let visible = (NSScreen.screens.first { $0.frame.intersects(anchor) } ?? NSScreen.main)?.visibleFrame {
            origin.x = min(max(origin.x, visible.minX), visible.maxX - size.width)
            if origin.y + size.height > visible.maxY { origin.y = anchor.minY - Self.gap - size.height }
        }
        panel.setFrame(NSRect(origin: origin, size: size), display: true)
        panel.orderFrontRegardless()
    }

    private static func makePanel() -> NSPanel {
        let panel = NSPanel(
            contentRect: .zero, styleMask: [.borderless, .nonactivatingPanel], backing: .buffered,
            defer: true)
        panel.level = NSWindow.Level(rawValue: NSWindow.Level.floating.rawValue + 1)
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        panel.ignoresMouseEvents = true
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = false
        panel.animationBehavior = .none
        panel.isReleasedWhenClosed = false
        return panel
    }
}
