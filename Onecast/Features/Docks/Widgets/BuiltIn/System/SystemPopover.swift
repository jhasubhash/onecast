import SwiftUI

/// What every System popover agrees on: one width, one inset, one body height.
enum SystemPopover {
    static let width: CGFloat = 340
    static let padding: CGFloat = Theme.Spacing.xl
    /// A tabbed or scrolling body holds this height, so switching tabs never resizes the popover.
    static let bodyHeight: CGFloat = 300
}
