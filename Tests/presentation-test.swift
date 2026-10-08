import CoreGraphics
import Foundation

@main
@MainActor
struct PresentationTests {
    static var failures = 0
    static var passes = 0

    static func expect(_ condition: @autoclosure () -> Bool, _ message: String) {
        if condition() {
            passes += 1
        } else {
            failures += 1
            print("FAIL: \(message)")
        }
    }

    static func main() {
        aChoiceIgnoresTheRefreshRate()
        choicesListOnePerSizeLargestFirst()
        aStoredChoiceResolvesToTheFastestMode()
        theMarginInsetsEverySideOfTheUsableArea()
        anOutOfRangeMarginIsClamped()
        fullScreenAndUnchangedHaveNoFrame()
        scopesReachTheWindowsTheyName()
        anAXFrameMatchesItsQuartzReadingWithinAPoint()

        print("\(passes) passed, \(failures) failed")
        if failures > 0 { exit(1) }
    }

    private static func mode(
        _ width: Int, _ height: Int, scale: Int = 2, hz: Double = 60
    ) -> PresentationDisplayMode {
        PresentationDisplayMode(
            width: width, height: height, pixelWidth: width * scale, pixelHeight: height * scale,
            refreshRate: hz)
    }

    static func aChoiceIgnoresTheRefreshRate() {
        expect(
            mode(1920, 1080, hz: 60).id == mode(1920, 1080, hz: 144).id,
            "a different cable's refresh rate still finds the stored choice")
        expect(
            mode(1920, 1080, scale: 2).id != mode(1920, 1080, scale: 1).id,
            "HiDPI and low resolution at one size are different choices")
        expect(mode(1920, 1080, scale: 1).title.contains("low resolution"), "1x is labelled")
    }

    static func choicesListOnePerSizeLargestFirst() {
        let choices = PresentationResolutionPolicy.choices(from: [
            mode(1920, 1080, scale: 1), mode(2560, 1440, hz: 30), mode(1920, 1080),
            mode(2560, 1440, hz: 60), mode(3840, 2160, scale: 1),
        ])
        expect(
            choices.map(\.id) == ["3840x2160@1x", "2560x1440@2x", "1920x1080@2x", "1920x1080@1x"],
            "one entry per size and scale, largest first, HiDPI ahead of 1x")
        expect(choices[1].refreshRate == 60, "the kept duplicate is the faster one")
    }

    static func aStoredChoiceResolvesToTheFastestMode() {
        let modes = [mode(1920, 1080, hz: 60), mode(2560, 1440), mode(1920, 1080, hz: 120)]
        expect(
            PresentationResolutionPolicy.index(of: "1920x1080@2x", in: modes) == 2,
            "the fastest matching mode is switched to")
        expect(
            PresentationResolutionPolicy.index(of: "1280x720@2x", in: modes) == nil,
            "a display without the size has no mode to switch to")
    }

    private static let usable = CGRect(x: 0, y: 25, width: 2000, height: 1000)

    static func theMarginInsetsEverySideOfTheUsableArea() {
        expect(
            PresentationFrameEngine.frame(for: .margin, marginPercent: 10, in: usable)
                == CGRect(x: 200, y: 125, width: 1600, height: 800),
            "10% comes off each side, of width and of height")
        expect(
            PresentationFrameEngine.frame(for: .fill, marginPercent: 10, in: usable) == usable,
            "fill takes the whole usable area whatever the margin")
    }

    static func anOutOfRangeMarginIsClamped() {
        let frame = PresentationFrameEngine.frame(for: .margin, marginPercent: 80, in: usable)
        expect(
            frame == usable.insetBy(dx: 600, dy: 300),
            "a margin past the range is clamped, never inverting the frame")
    }

    static func fullScreenAndUnchangedHaveNoFrame() {
        expect(
            PresentationFrameEngine.frame(for: .fullScreen, marginPercent: 10, in: usable) == nil,
            "full screen is not a frame")
        expect(
            PresentationFrameEngine.frame(for: .unchanged, marginPercent: 10, in: usable) == nil,
            "leaving the window be is not a frame")
    }
}

extension PresentationTests {
    private static let monitor = CGRect(x: 1512, y: -400, width: 3008, height: 1692)
    private static let onScreen = [
        PresentationWindow(pid: 1, frame: CGRect(x: 100, y: 100, width: 800, height: 600)),
        PresentationWindow(pid: 2, frame: CGRect(x: 2000, y: 0, width: 1200, height: 800)),
        PresentationWindow(pid: 2, frame: CGRect(x: 200, y: 200, width: 400, height: 300)),
    ]

    static func scopesReachTheWindowsTheyName() {
        expect(
            PresentationScopePolicy.reach(.everywhere, onScreen: onScreen, display: monitor) == nil,
            "every Space reaches every window, not only those on screen")
        let current = PresentationScopePolicy.reach(.currentSpace, onScreen: onScreen, display: monitor)
        expect(current?[1]?.count == 1 && current?[2]?.count == 2, "the current Space reaches every display")
        expect(current?[3] == nil, "an app with nothing on screen is left alone")
        let shared = PresentationScopePolicy.reach(
            .presentationDisplay, onScreen: onScreen, display: monitor)
        expect(shared?[1] == nil, "a window on another display is left where it is")
        expect(
            shared?[2] == [CGRect(x: 2000, y: 0, width: 1200, height: 800)],
            "only the app's window on the shared display is reached")
    }

    static func anAXFrameMatchesItsQuartzReadingWithinAPoint() {
        let quartz = [CGRect(x: 2000, y: 0, width: 1200, height: 800)]
        expect(
            PresentationScopePolicy.matches(CGRect(x: 2001, y: 0, width: 1199, height: 801), anyOf: quartz),
            "a point of rounding still names the same window")
        expect(
            !PresentationScopePolicy.matches(CGRect(x: 2000, y: 40, width: 1200, height: 800), anyOf: quartz),
            "a window elsewhere is another window")
    }
}
