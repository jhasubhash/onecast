import SwiftUI

/// Lays its children along the dock's axis: side by side on a bottom dock, stacked on a side one.
struct TimeAxisStack<Content: View>: View {
    let isVertical: Bool
    var spacing: CGFloat = 0
    @ViewBuilder let content: Content

    var body: some View {
        let layout =
            isVertical
            ? AnyLayout(VStackLayout(spacing: spacing)) : AnyLayout(HStackLayout(spacing: spacing))
        layout { content }
    }
}
