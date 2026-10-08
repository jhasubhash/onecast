import AppKit
import Carbon.HIToolbox
import SwiftUI

@MainActor
@Observable
final class DictationDisplayState {
    enum Phase { case listening, transcribing }
    var phase: Phase = .listening
    var levels = [Float](repeating: 0, count: DictationSpectrum.barCount)
    /// Set before `show()`: a live session sizes the panel for its preview line.
    var isLive = false
    var preview = ""
}

private struct DictationWaveform: View {
    let levels: [Float]
    let processing: Bool

    var body: some View {
        HStack(alignment: .center, spacing: Theme.Spacing.dictationWaveGap) {
            ForEach(levels.indices, id: \.self) { index in
                let emphasis =
                    processing
                    ? Double(levels[index])
                    : min(1, Double(min(index, levels.count - 1 - index)) / 3)
                Capsule()
                    .fill(Theme.Colors.textPrimary.opacity(0.4 + 0.6 * emphasis))
                    .frame(
                        width: Theme.Size.dictationWaveBar,
                        height: 3 + (processing ? 9 : 25) * CGFloat(levels[index]))
            }
        }
        .animation(.easeOut(duration: 0.06), value: levels)
    }
}

private struct DictationProcessingWave: View {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var startedAt = Date()

    var body: some View {
        TimelineView(.animation(minimumInterval: 1.0 / 30, paused: reduceMotion)) { timeline in
            let progress =
                timeline.date.timeIntervalSince(startedAt)
                .truncatingRemainder(dividingBy: 1.2) / 1.2
            let center = (reduceMotion ? 0.5 : progress) * 28 - 4
            DictationWaveform(
                levels: (0..<DictationSpectrum.barCount).map { index in
                    Float(max(0, 1 - abs(Double(index) - center) / 4))
                }, processing: true)
        }
    }
}

private struct DictationPanelView: View {
    let state: DictationDisplayState

    var body: some View {
        VStack(spacing: Theme.Spacing.sm) {
            if state.isLive {
                Text(state.preview)
                    .font(.callout)
                    .lineLimit(1)
                    .truncationMode(.head)
                    .padding(.horizontal, Theme.Spacing.lg)
                    .frame(height: Theme.Size.dictationPreview.height)
                    .glassEffect(.regular, in: .capsule)
                    .opacity(state.preview.isEmpty ? 0 : 1)
                    .frame(maxWidth: Theme.Size.dictationPreview.width)
                    .accessibilityLabel("Words still being recognized")
            }
            capsule
        }
        .frame(
            width: DictationPanelController.size(isLive: state.isLive).width,
            height: DictationPanelController.size(isLive: state.isLive).height, alignment: .bottom)
    }

    private var capsule: some View {
        Group {
            if state.phase == .listening {
                DictationWaveform(
                    levels: state.levels.enumerated().map { index, level in
                        let edge = min(1, Float(min(index, state.levels.count - 1 - index)) / 4)
                        let taper = edge * edge * (3 - 2 * edge)
                        return level * (0.2 + 0.8 * taper)
                    }, processing: false
                )
                .accessibilityLabel("Dictation listening")
            } else {
                DictationProcessingWave()
                    .accessibilityLabel("Transcribing dictation")
            }
        }
        .frame(width: Theme.Size.dictationPanel.width, height: Theme.Size.dictationPanel.height)
        .glassEffect(.regular, in: .capsule)
    }
}

private final class DictationPanel: NSPanel {
    var onAccept: (() -> Void)?
    var onCancel: (() -> Void)?

    init(content: NSView, size: CGSize) {
        super.init(
            contentRect: NSRect(origin: .zero, size: size),
            styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false)
        nameForAccessibility("dictation", title: "Dictation")
        contentView = content
        isOpaque = false
        backgroundColor = .clear
        hasShadow = true
        level = .floating
        collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        hidesOnDeactivate = false
        isReleasedWhenClosed = false
        animationBehavior = .none
    }

    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { false }

    override func sendEvent(_ event: NSEvent) {
        if event.type == .keyDown, !event.isARepeat {
            switch Int(event.keyCode) {
            case kVK_Return, kVK_ANSI_KeypadEnter: onAccept?(); return
            case kVK_Escape: onCancel?(); return
            default: break
            }
        }
        super.sendEvent(event)
    }
}

@MainActor
final class DictationPanelController {
    let state = DictationDisplayState()
    private var panel: DictationPanel?
    var onAccept: (() -> Void)?
    var onCancel: (() -> Void)?

    /// The capsule's place stays put; a live panel only grows upward and wider for its preview.
    static func size(isLive: Bool) -> CGSize {
        let capsule = Theme.Size.dictationPanel
        guard isLive else { return capsule }
        let preview = Theme.Size.dictationPreview
        return CGSize(
            width: max(capsule.width, preview.width),
            height: capsule.height + Theme.Spacing.sm + preview.height)
    }

    func show() {
        let screen = NSScreen.main ?? NSScreen.screens.first
        guard let frame = screen?.visibleFrame else { return }
        let size = Self.size(isLive: state.isLive)
        let panel =
            panel
            ?? DictationPanel(
                content: NSHostingView(rootView: DictationPanelView(state: state)), size: size)
        panel.onAccept = onAccept
        panel.onCancel = onCancel
        self.panel = panel
        panel.setFrameOrigin(
            NSPoint(
                x: frame.midX - size.width / 2,
                y: frame.minY + frame.height * 0.1 - Theme.Size.dictationPanel.height / 2))
        state.phase = .listening
        state.preview = ""
        state.levels = [Float](repeating: 0, count: DictationSpectrum.barCount)
        panel.makeKeyAndOrderFront(nil)
    }

    func close() {
        panel?.orderOut(nil)
        panel = nil
    }
}
