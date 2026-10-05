import AppKit
import ImageIO
import ScreenCaptureKit
import UniformTypeIdentifiers

/// Window snapshots: a bounded in-memory set, mirrored to disk so a restart keeps the minimized.
@MainActor
final class DockPreviewStore {
    static let capacity = 64
    /// Longest edge, in pixels: a tile's hover preview, never a screenshot to read.
    nonisolated static let maxPixel = 256

    private var images: [String: NSImage] = [:]
    /// Least recently stored first, so the bound evicts from the front.
    private var order: [String] = []

    func image(for token: String) -> NSImage? { images[token] }

    /// Decodes and keeps `png`; false when it is not an image.
    @discardableResult
    func insert(_ png: Data, for token: String) -> Bool {
        guard let image = NSImage(data: png) else { return false }
        images[token] = image
        order.removeAll { $0 == token }
        order.append(token)
        while order.count > Self.capacity { images[order.removeFirst()] = nil }
        return true
    }

    func evict(_ token: String) {
        images[token] = nil
        order.removeAll { $0 == token }
        Task.detached(priority: .utility) {
            try? FileManager.default.removeItem(at: Self.file(for: token))
        }
    }

    func evictAll() {
        images = [:]
        order = []
        Task.detached(priority: .utility) {
            try? FileManager.default.removeItem(at: Self.directory())
        }
    }

    // MARK: - Disk and capture

    private nonisolated static func directory() -> URL {
        AppPaths.caches().appending(path: "DockWindowPreviews", directoryHint: .isDirectory)
    }

    private nonisolated static func file(for token: String) -> URL {
        directory().appending(path: token + ".png", directoryHint: .notDirectory)
    }

    nonisolated static func persist(_ png: Data, for token: String) {
        try? FileManager.default.createDirectory(at: directory(), withIntermediateDirectories: true)
        try? png.write(to: file(for: token), options: .atomic)
    }

    /// The saved PNG of each token that has one.
    nonisolated static func load(_ tokens: [String]) -> [String: Data] {
        var loaded: [String: Data] = [:]
        for token in tokens {
            if let data = try? Data(contentsOf: file(for: token)) { loaded[token] = data }
        }
        return loaded
    }

    /// Windows are numbered afresh each boot, so what belongs to no live window is stale.
    nonisolated static func purge(keeping tokens: Set<String>) {
        let names = (try? FileManager.default.contentsOfDirectory(atPath: directory().path)) ?? []
        for name in names where !tokens.contains((name as NSString).deletingPathExtension) {
            try? FileManager.default.removeItem(at: directory().appending(path: name))
        }
    }

    /// A PNG of the window, downscaled; nil when it is not on screen or capture is refused.
    nonisolated static func capture(windowID: CGWindowID) async -> Data? {
        guard
            let content = try? await SCShareableContent.excludingDesktopWindows(
                true, onScreenWindowsOnly: true),
            let window = content.windows.first(where: { $0.windowID == windowID }),
            window.frame.width >= 1, window.frame.height >= 1
        else { return nil }
        let scale = min(1, CGFloat(maxPixel) / max(window.frame.width, window.frame.height))
        let configuration = SCStreamConfiguration()
        configuration.width = max(1, Int((window.frame.width * scale).rounded()))
        configuration.height = max(1, Int((window.frame.height * scale).rounded()))
        configuration.showsCursor = false
        configuration.ignoreShadowsSingleWindow = true
        guard
            let image = try? await SCScreenshotManager.captureImage(
                contentFilter: SCContentFilter(desktopIndependentWindow: window),
                configuration: configuration)
        else { return nil }
        return png(image)
    }

    private nonisolated static func png(_ image: CGImage) -> Data? {
        let data = NSMutableData()
        guard
            let destination = CGImageDestinationCreateWithData(
                data, UTType.png.identifier as CFString, 1, nil)
        else { return nil }
        CGImageDestinationAddImage(destination, image, nil)
        return CGImageDestinationFinalize(destination) ? data as Data : nil
    }
}
