#if DEBUG
import AppKit
import ScreenCaptureKit

/// One window to a PNG: ScreenCaptureKit when granted, else the view's own cached drawing.
@MainActor
enum AgentWindowCapture {
    enum Failure: Error, LocalizedError {
        case notOnScreen
        case unencodable
        case unwritable(String)

        var errorDescription: String? {
            switch self {
            case .notOnScreen: "The window is not on screen."
            case .unencodable: "The capture could not be encoded as PNG."
            case .unwritable(let path): "Could not write \(path)."
            }
        }
    }

    static func capture(
        _ window: NSWindow, id: String, to path: String?
    ) async throws -> AgentSnapshot.Capture {
        let (image, method) =
            if Permissions.isScreenRecordingTrusted() {
                (try await screenCapture(window), "screenCaptureKit")
            } else {
                (try cachedDrawing(window), "cacheDisplay")
            }
        guard let data = NSBitmapImageRep(cgImage: image).representation(using: .png, properties: [:])
        else { throw Failure.unencodable }
        let url = path.map { URL(fileURLWithPath: ($0 as NSString).expandingTildeInPath) } ?? temporaryURL(id)
        do {
            try FileManager.default.createDirectory(
                at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
            try data.write(to: url)
        } catch {
            throw Failure.unwritable(url.path)
        }
        return AgentSnapshot.Capture(
            path: url.path, window: id, frame: AgentWindowInspector.rect(window.frame),
            pixelWidth: image.width, pixelHeight: image.height, method: method)
    }

    private static func screenCapture(_ window: NSWindow) async throws -> CGImage {
        let content = try await SCShareableContent.excludingDesktopWindows(
            false, onScreenWindowsOnly: true)
        let number = CGWindowID(window.windowNumber)
        guard let target = content.windows.first(where: { $0.windowID == number }) else {
            throw Failure.notOnScreen
        }
        let configuration = SCStreamConfiguration()
        let scale = window.backingScaleFactor
        configuration.width = Int(target.frame.width * scale)
        configuration.height = Int(target.frame.height * scale)
        configuration.showsCursor = false
        configuration.ignoreShadowsSingleWindow = true
        return try await SCScreenshotManager.captureImage(
            contentFilter: SCContentFilter(desktopIndependentWindow: target),
            configuration: configuration)
    }

    private static func cachedDrawing(_ window: NSWindow) throws -> CGImage {
        let scale = window.backingScaleFactor
        guard let view = window.contentView,
            let representation = NSBitmapImageRep(
                bitmapDataPlanes: nil, pixelsWide: Int(view.bounds.width * scale),
                pixelsHigh: Int(view.bounds.height * scale), bitsPerSample: 8, samplesPerPixel: 4,
                hasAlpha: true, isPlanar: false, colorSpaceName: .deviceRGB, bytesPerRow: 0,
                bitsPerPixel: 0)
        else { throw Failure.notOnScreen }
        representation.size = view.bounds.size
        view.cacheDisplay(in: view.bounds, to: representation)
        guard let image = representation.cgImage else { throw Failure.unencodable }
        return image
    }

    private static func temporaryURL(_ id: String) -> URL {
        let name = id.replacingOccurrences(of: "#", with: "-")
        let stamp = Int(Date().timeIntervalSince1970 * 1000)
        return FileManager.default.temporaryDirectory
            .appendingPathComponent("onecast-agent", isDirectory: true)
            .appendingPathComponent("\(name)-\(stamp).png")
    }
}
#endif
