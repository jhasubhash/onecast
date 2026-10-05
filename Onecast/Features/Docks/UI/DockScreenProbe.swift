import AppKit
import CoreGraphics

/// What the docks ask of the window server: whether another app fills a display, and whether
/// the macOS Dock is out on an edge.
enum DockScreenProbe {
    /// Core Graphics' coordinates put the origin at the top left of the menu-bar display.
    nonisolated private static func quartzRect(of screenFrame: CGRect) -> CGRect {
        let primaryHeight = CGDisplayBounds(CGMainDisplayID()).height
        return CGRect(
            x: screenFrame.minX, y: primaryHeight - screenFrame.maxY, width: screenFrame.width,
            height: screenFrame.height)
    }

    nonisolated private static func onScreenWindows() -> [[String: Any]] {
        let options: CGWindowListOption = [.optionOnScreenOnly, .excludeDesktopElements]
        return (CGWindowListCopyWindowInfo(options, kCGNullWindowID) as? [[String: Any]]) ?? []
    }

    nonisolated private static func bounds(of window: [String: Any]) -> CGRect? {
        guard let dictionary = window[kCGWindowBounds as String] as? [String: Any] else {
            return nil
        }
        return CGRect(dictionaryRepresentation: dictionary as CFDictionary)
    }

    /// A full-screen app's window covers the whole display, menu bar included.
    nonisolated static func hasFullScreenWindow(on screenFrame: CGRect) -> Bool {
        let screen = quartzRect(of: screenFrame)
        let ownProcessID = Int(ProcessInfo.processInfo.processIdentifier)
        return onScreenWindows().contains { window in
            guard window[kCGWindowLayer as String] as? Int == 0,
                window[kCGWindowOwnerPID as String] as? Int != ownProcessID,
                let bounds = bounds(of: window)
            else { return false }
            return abs(bounds.minX - screen.minX) < 1 && abs(bounds.minY - screen.minY) < 1
                && abs(bounds.width - screen.width) < 1 && abs(bounds.height - screen.height) < 1
        }
    }

    /// The Dock's window sits at the Dock level and is moved off screen while it is hidden, so
    /// it counts as revealed once enough of it lies over `edge` of the display.
    nonisolated static func macOSDockIsRevealed(edge: DockEdge, on screenFrame: CGRect) -> Bool {
        let screen = quartzRect(of: screenFrame)
        let dockLevel = Int(CGWindowLevelForKey(.dockWindow))
        return onScreenWindows().contains { window in
            guard window[kCGWindowOwnerName as String] as? String == "Dock",
                window[kCGWindowLayer as String] as? Int == dockLevel,
                let bounds = bounds(of: window)
            else { return false }
            let overlap = bounds.intersection(screen)
            guard !overlap.isNull else { return false }
            switch edge {
            case .bottom:
                return bounds.maxY >= screen.maxY - 2 && overlap.height >= minimumRevealed
                    && overlap.height < screen.height / 2
            case .left:
                return bounds.minX <= screen.minX + 2 && overlap.width >= minimumRevealed
                    && overlap.width < screen.width / 2
            case .right:
                return bounds.maxX >= screen.maxX - 2 && overlap.width >= minimumRevealed
                    && overlap.width < screen.width / 2
            }
        }
    }

    /// A sliver left over by a hiding Dock does not count as revealed.
    private static let minimumRevealed: CGFloat = 12
}
