import SwiftUI

/// An analog clock face whose hands follow `angles`; it fills the square it is offered.
struct TimeAnalogFaceView: View {
    let angles: TimeTick.Angles
    let showsSecondHand: Bool

    private static let tickCount = 12
    private static let tickLength: CGFloat = 0.07
    private static let tickInset: CGFloat = 0.05
    private static let hourHand: (length: CGFloat, width: CGFloat) = (0.5, 0.045)
    private static let minuteHand: (length: CGFloat, width: CGFloat) = (0.74, 0.03)
    private static let secondHand: (length: CGFloat, width: CGFloat) = (0.82, 0.012)
    private static let hub: CGFloat = 0.07
    private static let rimWidth: CGFloat = 0.012
    private static let tickWidth: CGFloat = 0.015

    var body: some View {
        GeometryReader { proxy in
            let side = min(proxy.size.width, proxy.size.height)
            ZStack {
                Circle().fill(Theme.Colors.cardFill)
                Circle().strokeBorder(Theme.Colors.cardStroke, lineWidth: max(1, side * Self.rimWidth))
                ForEach(0..<Self.tickCount, id: \.self) { index in
                    Capsule()
                        .fill(index % 3 == 0 ? Theme.Colors.textPrimary : Theme.Colors.textTertiary)
                        .frame(width: max(1, side * Self.tickWidth), height: side * Self.tickLength)
                        .offset(y: -(side / 2 - side * (Self.tickLength / 2 + Self.tickInset)))
                        .rotationEffect(.degrees(Double(index) * 360 / Double(Self.tickCount)))
                }
                hand(angles.hour, Self.hourHand, side: side, color: Theme.Colors.textPrimary)
                hand(angles.minute, Self.minuteHand, side: side, color: Theme.Colors.textPrimary)
                if showsSecondHand {
                    hand(angles.second, Self.secondHand, side: side, color: Theme.Colors.warning)
                }
                Circle().fill(Theme.Colors.textPrimary).frame(width: side * Self.hub)
            }
            .frame(width: side, height: side)
            .position(x: proxy.size.width / 2, y: proxy.size.height / 2)
        }
        .aspectRatio(1, contentMode: .fit)
    }

    private func hand(
        _ angle: Double, _ shape: (length: CGFloat, width: CGFloat), side: CGFloat, color: Color
    ) -> some View {
        let length = side / 2 * shape.length
        return Capsule()
            .fill(color)
            .frame(width: max(1, side * shape.width), height: length)
            .offset(y: -length / 2)
            .rotationEffect(.degrees(angle))
    }
}
