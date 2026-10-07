import AppKit

/// Every CoreGraphics display-mode call: a display's modes, and switching one.
@MainActor
enum PresentationDisplayAccess {
    /// A connected display as the resolution picker lists it.
    struct Display: Identifiable {
        let id: CGDirectDisplayID
        /// `NSScreen.displayKey`: survives a replug, so a stored choice finds its display again.
        let key: String
        let name: String
    }

    private static let settlePoll: Duration = .milliseconds(100)
    private static let settleLimit = 30
    /// The Dock and menu bar re-lay themselves out just after AppKit reports the new size.
    private static let settleGrace: Duration = .milliseconds(400)

    static func displays() -> [Display] {
        NSScreen.screens.compactMap { screen in
            displayID(of: screen).map {
                Display(id: $0, key: screen.displayKey, name: screen.localizedName)
            }
        }
    }

    static func displayID(of screen: NSScreen) -> CGDirectDisplayID? {
        (screen.deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? NSNumber)?
            .uint32Value
    }

    static func screen(for display: CGDirectDisplayID) -> NSScreen? {
        NSScreen.screens.first { displayID(of: $0) == display }
    }

    /// Usable on the desktop, HiDPI duplicates included: those are the modes that read well.
    static func modes(of display: CGDirectDisplayID) -> [CGDisplayMode] {
        let options = [kCGDisplayShowDuplicateLowResolutionModes: kCFBooleanTrue] as CFDictionary
        let modes = CGDisplayCopyAllDisplayModes(display, options) as? [CGDisplayMode] ?? []
        return modes.filter { $0.isUsableForDesktopGUI() }
    }

    static func currentMode(of display: CGDirectDisplayID) -> CGDisplayMode? {
        CGDisplayCopyDisplayMode(display)
    }

    static func model(of mode: CGDisplayMode) -> PresentationDisplayMode {
        PresentationDisplayMode(
            width: mode.width, height: mode.height, pixelWidth: mode.pixelWidth,
            pixelHeight: mode.pixelHeight, refreshRate: mode.refreshRate)
    }

    /// The concrete mode `id` names on `display`, nil when it offers no such mode.
    static func mode(id: String, on display: CGDirectDisplayID) -> CGDisplayMode? {
        let modes = modes(of: display)
        return PresentationResolutionPolicy.index(of: id, in: modes.map(model(of:))).map { modes[$0] }
    }

    /// Lasts only as long as Onecast runs: a quit or a crash puts the user's own mode back.
    static func set(_ mode: CGDisplayMode, on display: CGDirectDisplayID) -> Bool {
        CGDisplaySetDisplayMode(display, mode, nil) == .success
    }

    /// Waits for AppKit to report `display` at `mode`'s size, so a layout reads the new frames.
    static func settle(_ display: CGDirectDisplayID, at mode: CGDisplayMode) async {
        let size = CGSize(width: mode.width, height: mode.height)
        for _ in 0..<settleLimit {
            if screen(for: display)?.frame.size == size { break }
            try? await Task.sleep(for: settlePoll)
        }
        try? await Task.sleep(for: settleGrace)
    }
}
