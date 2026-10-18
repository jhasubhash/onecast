import SwiftUI

/// The running script: words said fade, the current word lights up, and the line ahead stays in view.
struct TeleprompterView: View {
    let coordinator: TeleprompterCoordinator
    let placement: TeleprompterPlacement
    let topInset: CGFloat
    @State private var hovered = false

    private static let notchRadius: CGFloat = 26
    private static let readingLine = UnitPoint(x: 0.5, y: 0.2)

    var body: some View {
        VStack(spacing: 0) {
            Color.clear.frame(height: topInset)
            script
            controls
        }
        .background(background)
        .clipShape(shape)
        .onHover { hovered = $0 }
        .environment(\.colorScheme, .dark)
    }

    private var shape: some Shape {
        placement == .notch
            ? AnyShape(
                UnevenRoundedRectangle(
                    bottomLeadingRadius: Self.notchRadius, bottomTrailingRadius: Self.notchRadius,
                    style: .continuous))
            : AnyShape(RoundedRectangle(cornerRadius: Theme.Radius.dialog, style: .continuous))
    }

    @ViewBuilder
    private var background: some View {
        if placement == .notch {
            Color.black
        } else {
            ZStack {
                GlassEffectView()
                Color.black.opacity(0.55)
            }
        }
    }

    private var script: some View {
        let current = coordinator.currentWord
        let size = CGFloat(coordinator.settings.teleprompterTextSize)
        return ScrollViewReader { reader in
            ScrollView {
                ScriptFlow(spacing: size * 0.3, lineSpacing: size * 0.35, paragraphSpacing: size * 0.6) {
                    ForEach(Array(coordinator.script.words.enumerated()), id: \.offset) { index, word in
                        Text(word.text)
                            .font(.system(size: size, weight: .semibold, design: .rounded).italic(word.isCue))
                            .foregroundStyle(color(index: index, current: current, word: word))
                            .id(index)
                            .layoutValue(key: ParagraphStart.self, value: word.breaksBefore)
                    }
                }
                .padding(.horizontal, Theme.Spacing.xxl)
                .padding(.vertical, size)
            }
            .scrollDisabled(true)
            .scrollIndicators(.hidden)
            .onChange(of: current, initial: true) { _, word in
                withAnimation(.easeInOut(duration: 0.35)) {
                    reader.scrollTo(min(word, max(coordinator.script.words.count - 1, 0)), anchor: Self.readingLine)
                }
            }
        }
        .mask(
            LinearGradient(
                stops: [
                    .init(color: .clear, location: 0), .init(color: .black, location: 0.12),
                    .init(color: .black, location: 0.85), .init(color: .clear, location: 1)
                ], startPoint: .top, endPoint: .bottom))
    }

    private func color(index: Int, current: Int, word: TeleprompterScript.Word) -> Color {
        if word.isCue { return .white.opacity(0.4) }
        if index < current { return .white.opacity(0.32) }
        if index == current { return coordinator.settings.teleprompterHighlight.color }
        return .white.opacity(0.92)
    }

    private var controls: some View {
        HStack(spacing: Theme.Spacing.md) {
            if coordinator.settings.teleprompterMode.usesMicrophone {
                Image(systemName: coordinator.isSpeaking ? "mic.fill" : "mic")
                    .foregroundStyle(coordinator.isSpeaking ? Color.green : .white.opacity(0.5))
                    .frame(width: Theme.Size.barButtonHeight)
            }
            Text("\(min(coordinator.currentWord, coordinator.script.words.count))/\(coordinator.script.words.count)")
                .font(.caption.monospacedDigit())
                .foregroundStyle(.white.opacity(0.5))
            Spacer(minLength: 0)
            PrompterButton(symbol: "backward.end.fill", action: coordinator.restart)
            PrompterButton(
                symbol: coordinator.isPaused ? "play.fill" : "pause.fill", action: coordinator.togglePause)
            PrompterButton(symbol: "xmark", action: coordinator.stop)
        }
        .padding(.horizontal, Theme.Spacing.xl)
        .frame(height: Theme.Size.barButtonHeight + Theme.Spacing.md * 2)
        .opacity(hovered || coordinator.isPaused ? 1 : 0.0)
        .animation(.easeOut(duration: Theme.Duration.hover), value: hovered)
    }
}

private struct PrompterButton: View {
    let symbol: String
    let action: () -> Void
    @State private var hovered = false

    var body: some View {
        Button(action: action) {
            Image(systemName: symbol)
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(.white.opacity(hovered ? 1 : 0.7))
                .frame(width: Theme.Size.barButtonHeight, height: Theme.Size.barButtonHeight)
                .background(Circle().fill(.white.opacity(hovered ? 0.18 : 0.08)))
                .contentShape(Circle())
        }
        .buttonStyle(.plain)
        .onHover { hovered = $0 }
    }
}

extension TeleprompterHighlight {
    var color: Color {
        switch self {
        case .yellow: .yellow
        case .green: .green
        case .blue: Color(red: 0.4, green: 0.7, blue: 1)
        case .pink: .pink
        case .orange: .orange
        case .white: .white
        }
    }
}

private struct ParagraphStart: LayoutValueKey {
    static let defaultValue = false
}

/// Words left to right, wrapping at the edge and breaking where the script starts a paragraph.
private struct ScriptFlow: Layout {
    let spacing: CGFloat
    let lineSpacing: CGFloat
    let paragraphSpacing: CGFloat

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let width = proposal.width ?? .infinity
        let frames = arrange(subviews, width: width)
        let height = frames.map(\.maxY).max() ?? 0
        return CGSize(width: proposal.width ?? frames.map(\.maxX).max() ?? 0, height: height)
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        for (subview, frame) in zip(subviews, arrange(subviews, width: bounds.width)) {
            subview.place(
                at: CGPoint(x: bounds.minX + frame.minX, y: bounds.minY + frame.minY),
                proposal: ProposedViewSize(frame.size))
        }
    }

    private func arrange(_ subviews: Subviews, width: CGFloat) -> [CGRect] {
        var frames: [CGRect] = []
        var x: CGFloat = 0
        var y: CGFloat = 0
        var lineHeight: CGFloat = 0
        for subview in subviews {
            let size = subview.sizeThatFits(.unspecified)
            let newParagraph = subview[ParagraphStart.self] && !frames.isEmpty
            if newParagraph || (x > 0 && x + size.width > width) {
                y += lineHeight + (newParagraph ? paragraphSpacing : lineSpacing)
                x = 0
                lineHeight = 0
            }
            frames.append(CGRect(origin: CGPoint(x: x, y: y), size: size))
            x += size.width + spacing
            lineHeight = max(lineHeight, size.height)
        }
        return frames
    }
}
