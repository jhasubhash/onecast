import AppKit
import SwiftUI

/// What a note is written on: the colours the picker offers and the preference stores. A superset
/// of `DockColor`, so a note saved before the neutrals existed keeps its colour.
enum StickyPaperColor: String, CaseIterable, Sendable {
    case yellow, orange, red, pink, purple, blue, teal, green
    /// Greys from pale to nearly black; the dark ones carry light ink in either appearance.
    case silver, graphite, charcoal, black

    var title: String { rawValue.prefix(1).uppercased() + rawValue.dropFirst() }

    var isNeutral: Bool {
        switch self {
        case .silver, .graphite, .charcoal, .black: true
        default: false
        }
    }

    /// The vivid dot the picker shows for a hue; a neutral shows its own paper instead.
    var vividSwatch: Color? {
        isNeutral ? nil : DockColor(rawValue: rawValue)?.swatch
    }

    /// Paper as one appearance wears it: soft and light, or deep. Unless a text colour is chosen,
    /// the ink follows the paper's own brightness, not the appearance, so a dark paper in a light
    /// dock still reads.
    func paper(isDarkAppearance dark: Bool, ink choice: StickyInkColor = .automatic) -> StickyNotePaper {
        let rgb = dark ? darkRGB : lightRGB
        let luminance = 0.2126 * rgb.0 + 0.7152 * rgb.1 + 0.0722 * rgb.2
        let paperIsDark = luminance < 0.45
        let automatic = Color(.sRGB, white: paperIsDark ? 0.95 : 0.13, opacity: 1)
        let ink = choice.color(onDarkPaper: paperIsDark) ?? automatic
        return StickyNotePaper(
            fill: Color(.sRGB, red: rgb.0, green: rgb.1, blue: rgb.2),
            ink: ink,
            faintInk: ink.opacity(paperIsDark ? 0.62 : 0.55),
            isDark: paperIsDark)
    }

    private var lightRGB: (CGFloat, CGFloat, CGFloat) {
        switch self {
        case .yellow: (0.953, 0.816, 0.361)
        case .orange: (0.957, 0.710, 0.420)
        case .red: (0.957, 0.600, 0.580)
        case .pink: (0.957, 0.710, 0.800)
        case .purple: (0.769, 0.690, 0.941)
        case .blue: (0.627, 0.784, 0.957)
        case .teal: (0.553, 0.827, 0.820)
        case .green: (0.710, 0.863, 0.545)
        case .silver: (0.880, 0.880, 0.890)
        case .graphite: (0.620, 0.630, 0.650)
        case .charcoal: (0.270, 0.280, 0.300)
        case .black: (0.100, 0.100, 0.110)
        }
    }

    private var darkRGB: (CGFloat, CGFloat, CGFloat) {
        switch self {
        case .yellow: (0.420, 0.350, 0.110)
        case .orange: (0.440, 0.280, 0.120)
        case .red: (0.420, 0.200, 0.190)
        case .pink: (0.420, 0.220, 0.310)
        case .purple: (0.290, 0.220, 0.420)
        case .blue: (0.170, 0.270, 0.420)
        case .teal: (0.140, 0.340, 0.340)
        case .green: (0.190, 0.340, 0.200)
        case .silver: (0.380, 0.390, 0.410)
        case .graphite: (0.250, 0.260, 0.280)
        case .charcoal: (0.150, 0.155, 0.165)
        case .black: (0.055, 0.055, 0.060)
        }
    }
}

/// A paper colour as worn: the fill, and the ink that reads on it.
struct StickyNotePaper {
    let fill: Color
    let ink: Color
    let faintInk: Color
    /// Whether the paper is dark enough to take light ink.
    let isDark: Bool
}

/// The surface printed on the paper.
enum StickyPaperTexture: String, CaseIterable, Sendable {
    case plain, lined, legal, grid, dots, grain, linen

    var title: String {
        switch self {
        case .plain: "Plain"
        case .lined: "Lined"
        case .legal: "Legal"
        case .grid: "Grid"
        case .dots: "Dots"
        case .grain: "Grain"
        case .linen: "Linen"
        }
    }
}

/// A texture drawn in the paper's own ink, faint enough to sit behind text. `lineHeight` is the
/// note's line pitch, so rules fall under the lines of text; `top` and `leading` are where the
/// first line starts.
struct StickyPaperTextureView: View {
    let texture: StickyPaperTexture
    let ink: Color
    let lineHeight: CGFloat
    var top: CGFloat = 0
    var leading: CGFloat = 0

    var body: some View {
        Canvas { context, size in
            switch texture {
            case .plain:
                break
            case .lined, .legal:
                rules(&context, size)
                if texture == .legal { margin(&context, size) }
            case .grid:
                grid(&context, size)
            case .dots:
                dots(&context, size)
            case .grain:
                grain(&context, size)
            case .linen:
                linen(&context, size)
            }
        }
        .allowsHitTesting(false)
        .accessibilityHidden(true)
    }

    private func rules(_ context: inout GraphicsContext, _ size: CGSize) {
        var path = Path()
        var y = top + lineHeight * 0.9
        while y < size.height {
            path.move(to: CGPoint(x: 0, y: y))
            path.addLine(to: CGPoint(x: size.width, y: y))
            y += lineHeight
        }
        context.stroke(path, with: .color(ink.opacity(0.16)), lineWidth: 1)
    }

    /// A legal pad's double red margin, a little left of where the text starts.
    private func margin(_ context: inout GraphicsContext, _ size: CGSize) {
        let x = max(leading - lineHeight * 0.45, 4)
        var path = Path()
        for offset in [CGFloat(0), 3] {
            path.move(to: CGPoint(x: x + offset, y: 0))
            path.addLine(to: CGPoint(x: x + offset, y: size.height))
        }
        context.stroke(path, with: .color(Color.red.opacity(0.35)), lineWidth: 1)
    }

    private func grid(_ context: inout GraphicsContext, _ size: CGSize) {
        var path = Path()
        var x = leading.truncatingRemainder(dividingBy: lineHeight)
        while x < size.width {
            path.move(to: CGPoint(x: x, y: 0))
            path.addLine(to: CGPoint(x: x, y: size.height))
            x += lineHeight
        }
        var y = top.truncatingRemainder(dividingBy: lineHeight)
        while y < size.height {
            path.move(to: CGPoint(x: 0, y: y))
            path.addLine(to: CGPoint(x: size.width, y: y))
            y += lineHeight
        }
        context.stroke(path, with: .color(ink.opacity(0.11)), lineWidth: 1)
    }

    private func dots(_ context: inout GraphicsContext, _ size: CGSize) {
        let radius = max(lineHeight * 0.06, 0.8)
        var y = top.truncatingRemainder(dividingBy: lineHeight)
        while y < size.height {
            var x = leading.truncatingRemainder(dividingBy: lineHeight)
            while x < size.width {
                context.fill(
                    Path(ellipseIn: CGRect(x: x - radius, y: y - radius, width: radius * 2, height: radius * 2)),
                    with: .color(ink.opacity(0.26)))
                x += lineHeight
            }
            y += lineHeight
        }
    }

    /// Fine speckle from a fixed seed, so the same paper looks the same every time it is drawn.
    private func grain(_ context: inout GraphicsContext, _ size: CGSize) {
        var seed: UInt64 = 0x9E37_79B9_7F4A_7C15
        func next() -> CGFloat {
            seed = seed &* 6_364_136_223_846_793_005 &+ 1_442_695_040_888_963_407
            return CGFloat(seed >> 33) / CGFloat(1 << 31)
        }
        let count = Int(size.width * size.height / 40)
        for _ in 0..<count {
            let x = next() * size.width
            let y = next() * size.height
            let alpha = 0.03 + next() * 0.10
            context.fill(Path(CGRect(x: x, y: y, width: 1, height: 1)), with: .color(ink.opacity(alpha)))
        }
    }

    /// A woven look: two sets of hairlines crossing on the diagonal.
    private func linen(_ context: inout GraphicsContext, _ size: CGSize) {
        var path = Path()
        let step: CGFloat = 3
        var k = -size.height
        while k < size.width {
            path.move(to: CGPoint(x: k, y: 0))
            path.addLine(to: CGPoint(x: k + size.height, y: size.height))
            path.move(to: CGPoint(x: k + size.height, y: 0))
            path.addLine(to: CGPoint(x: k, y: size.height))
            k += step
        }
        context.stroke(path, with: .color(ink.opacity(0.05)), lineWidth: 0.6)
    }
}

extension StickyPaperTextureView {
    /// The height of one line of text in `size`-point system type, which is the pitch of its rules.
    static func lineHeight(forFontSize size: CGFloat) -> CGFloat {
        NSLayoutManager().defaultLineHeight(for: NSFont.systemFont(ofSize: size))
    }
}

/// The colour the text is written in. Automatic follows the paper, so it always reads; the others
/// are the author's choice, shown lighter on a dark paper so a hue keeps some contrast.
enum StickyInkColor: String, CaseIterable, Sendable {
    case automatic, black, white, blue, red, green, purple, brown

    var title: String { rawValue.prefix(1).uppercased() + rawValue.dropFirst() }

    /// nil for Automatic, which the paper decides.
    func color(onDarkPaper dark: Bool) -> Color? {
        let rgb: (CGFloat, CGFloat, CGFloat)
        switch self {
        case .automatic: return nil
        case .black: rgb = (0.06, 0.06, 0.07)
        case .white: rgb = (0.98, 0.98, 0.98)
        case .blue: rgb = dark ? (0.55, 0.72, 1.00) : (0.08, 0.24, 0.66)
        case .red: rgb = dark ? (1.00, 0.58, 0.56) : (0.70, 0.10, 0.12)
        case .green: rgb = dark ? (0.56, 0.88, 0.62) : (0.08, 0.44, 0.20)
        case .purple: rgb = dark ? (0.78, 0.64, 1.00) : (0.44, 0.18, 0.64)
        case .brown: rgb = dark ? (0.84, 0.66, 0.46) : (0.38, 0.24, 0.10)
        }
        return Color(.sRGB, red: rgb.0, green: rgb.1, blue: rgb.2)
    }
}
