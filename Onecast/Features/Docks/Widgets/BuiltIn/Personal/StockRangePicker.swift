import SwiftUI

/// The chart's range switch: five segments on one control surface, drawn from Theme tokens.
struct StockRangePicker: View {
    @Binding var selection: StockRange

    var body: some View {
        HStack(spacing: Theme.Spacing.xxs) {
            ForEach(StockRange.allCases) { range in
                Segment(range: range, isSelected: range == selection) { selection = range }
            }
        }
        .padding(Theme.Spacing.xxs)
        .background(
            RoundedRectangle(cornerRadius: Theme.Radius.card, style: .continuous)
                .fill(Theme.Colors.cardFill)
        )
        .accessibilityElement(children: .contain)
        .accessibilityLabel("Chart range")
    }

    private struct Segment: View {
        let range: StockRange
        let isSelected: Bool
        let action: () -> Void
        @State private var hovered = false

        var body: some View {
            Button(action: action) {
                Text(range.title)
                    .font(Theme.Typography.bar)
                    .foregroundStyle(isSelected ? Theme.Colors.textPrimary : Theme.Colors.textSecondary)
                    .frame(maxWidth: .infinity)
                    .frame(height: Theme.Size.barButtonHeight)
                    .background(
                        RoundedRectangle(cornerRadius: Theme.Radius.barControl, style: .continuous)
                            .fill(fill)
                    )
                    .contentShape(RoundedRectangle(cornerRadius: Theme.Radius.barControl, style: .continuous))
            }
            .buttonStyle(.plain)
            .onHover { hovered = $0 }
            .animation(.easeOut(duration: Theme.Duration.hover), value: hovered)
            .accessibilityLabel("\(range.title) chart")
            .accessibilityAddTraits(isSelected ? .isSelected : [])
        }

        private var fill: Color {
            if isSelected { return Theme.Colors.selection }
            return hovered ? Theme.Colors.rowHover : .clear
        }
    }
}
