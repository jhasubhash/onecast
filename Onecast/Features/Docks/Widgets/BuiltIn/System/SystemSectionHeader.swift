import SwiftUI

/// A popover's section heading.
struct SystemSectionHeader: View {
    let title: String

    var body: some View {
        Text(title)
            .font(Theme.Typography.sectionHeader)
            .foregroundStyle(Theme.Colors.textSecondary)
            .accessibilityAddTraits(.isHeader)
    }
}
