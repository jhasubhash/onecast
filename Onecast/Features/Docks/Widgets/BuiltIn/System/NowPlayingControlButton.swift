import SwiftUI

/// One transport button: a bare glyph that lifts a circle on hover.
struct NowPlayingControlButton: View {
    let control: SystemNowPlaying.Control
    let isPlaying: Bool
    let skipSeconds: Int
    let size: CGFloat
    var onHover: (Bool) -> Void = { _ in }
    let action: () -> Void
    @State private var hovered = false

    private static let glyphFraction: CGFloat = 0.5

    private var symbol: String {
        switch control {
        case .playPause: isPlaying ? "pause.fill" : "play.fill"
        case .previous: "backward.fill"
        case .next: "forward.fill"
        case .skipBack: "gobackward.\(skipSeconds)"
        case .skipForward: "goforward.\(skipSeconds)"
        }
    }

    private var label: String {
        switch control {
        case .playPause: isPlaying ? "Pause" : "Play"
        case .previous: "Previous Track"
        case .next: "Next Track"
        case .skipBack: "Back \(skipSeconds) Seconds"
        case .skipForward: "Forward \(skipSeconds) Seconds"
        }
    }

    var body: some View {
        Button(action: action) {
            SymbolImage(name: symbol, size: size * Self.glyphFraction)
                .foregroundStyle(Theme.Colors.textPrimary)
                .frame(width: size, height: size)
                .background(Circle().fill(hovered ? Theme.Colors.controlHover : Color.clear))
                .contentShape(Circle())
        }
        .buttonStyle(.plain)
        .onHover { hovering in
            hovered = hovering
            onHover(hovering)
        }
        .tooltip(label)
        .accessibilityLabel(label)
    }
}
