import SwiftUI

extension View {
    /// A focus edge for a palette form control: the system accent (`Color.accentColor`) tracing the
    /// control's own corner, with AppKit's blocky blue focus ring suppressed so this is the only
    /// highlight. `radius` matches the control, so the edge follows it rather than boxing it.
    func formFocusRing(_ focused: Bool, radius: CGFloat) -> some View {
        overlay(
            RoundedRectangle(cornerRadius: radius, style: .continuous)
                .strokeBorder(focused ? Color.accentColor : Color.clear, lineWidth: 1.5)
        )
        .focusEffectDisabled()
    }
}
