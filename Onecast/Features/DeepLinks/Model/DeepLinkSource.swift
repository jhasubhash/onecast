import Foundation

/// Where a link came from. One Onecast opened itself, from a quicklink, was chosen here.
enum DeepLinkSource: Sendable {
    case outside
    case onecast

    /// A quicklink reaching a quicklink could reach itself, and that loop never unwinds.
    func mayRun(_ action: HotKeyAction) -> Bool {
        guard self == .onecast, case .quicklink = action else { return true }
        return false
    }
}
