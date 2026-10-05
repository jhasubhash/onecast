import AppKit

/// Eases a dock's lens and pointer toward their targets once per display frame, so the lens moves
/// at the screen's own pace however unevenly mouse events arrive; it idles when both have settled.
@MainActor
final class DockLensDriver: NSObject {
    private let view: NSView
    private let onFrame: (_ seconds: Double) -> Bool
    private var link: CADisplayLink?

    /// `onFrame` advances by the frame's length and returns whether anything is still moving.
    init(view: NSView, onFrame: @escaping (_ seconds: Double) -> Bool) {
        self.view = view
        self.onFrame = onFrame
    }

    func start() {
        guard link == nil else { return }
        let link = view.displayLink(target: self, selector: #selector(step(_:)))
        link.add(to: .main, forMode: .common)
        self.link = link
    }

    func stop() {
        link?.invalidate()
        link = nil
    }

    @objc private func step(_ link: CADisplayLink) {
        if !onFrame(max(link.targetTimestamp - link.timestamp, 0)) { stop() }
    }

    /// Exponential approach: the same feel at any frame rate, never overshooting the target.
    static func approach(_ value: Double, to target: Double, seconds: Double, timeConstant: Double)
        -> Double
    {
        target + (value - target) * exp(-seconds / timeConstant)
    }
}
