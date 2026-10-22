import AppKit

/// Quick View: a clipboard image in a floating window of its own, decoded ahead so it opens at once.
@MainActor
final class ClipboardQuickView {
    private var cached: (url: URL, picture: Picture)?
    private var loading: (url: URL, task: Task<Picture?, Never>)?
    private var panel: ClipboardImagePanel?
    private var shownURL: URL?

    /// The entry's image: a blob the history holds, or a referenced file that is an image.
    static func imageURL(for item: ClipboardItem, store: ClipboardStore) -> URL? {
        switch item.kind {
        case .image:
            return store.imageURL(for: item)
        case .file:
            guard let path = item.filePath, ClipboardFileKind.of(path: path) == .image else { return nil }
            return URL(filePath: path, directoryHint: .notDirectory)
        case .text:
            return nil
        }
    }

    /// Called as the selection lands on a row, so the decode is done before anyone asks for it.
    func prefetch(_ url: URL?) {
        guard let url else {
            loading?.task.cancel()
            loading = nil
            if panel?.isVisible != true { cached = nil }
            return
        }
        guard cached?.url != url, loading?.url != url else { return }
        loading?.task.cancel()
        let task = Task { await Self.decode(url) }
        loading = (url, task)
        Task {
            let picture = await task.value
            guard loading?.url == url else { return }
            loading = nil
            if let picture { cached = (url, picture) }
        }
    }

    func show(_ url: URL, title: String, on screen: NSScreen?) {
        if let cached, cached.url == url {
            present(cached.picture, url: url, title: title, on: screen)
            return
        }
        prefetch(url)
        guard let task = loading?.task else { return }
        Task {
            guard let picture = await task.value else { return }
            present(picture, url: url, title: title, on: screen)
        }
    }

    /// Capped at its own size and the largest screen's: ImageIO would otherwise scale it up.
    private static func decode(_ url: URL) async -> Picture? {
        guard let pixels = ImageThumbnail.pixelSize(of: url) else { return nil }
        let screens = NSScreen.screens.map {
            max($0.frame.width, $0.frame.height) * $0.backingScaleFactor
        }
        let cap = min(max(pixels.width, pixels.height), screens.max() ?? 2048)
        guard let image = await ImageThumbnail.loadAsync(url, maxPixel: cap) else { return nil }
        let isFullSize = cap >= max(pixels.width, pixels.height)
        return Picture(image: image, pixels: pixels, isFullSize: isFullSize)
    }

    private func present(_ picture: Picture, url: URL, title: String, on screen: NSScreen?) {
        let panel = panel ?? ClipboardImagePanel()
        self.panel = panel
        shownURL = url
        panel.show(picture, title: title, on: screen ?? NSScreen.main)
        guard !picture.isFullSize else { return }
        // The screen-sized copy opens it at once; the full-resolution one replaces it once decoded.
        Task {
            let full = await ImageThumbnail.loadAsync(
                url, maxPixel: max(picture.pixels.width, picture.pixels.height))
            guard let full, shownURL == url, panel.isVisible else { return }
            panel.replaceImage(full)
        }
    }
}

/// The decoded bitmap, and the file's own pixel size, which a downsampled bitmap no longer has.
private struct Picture {
    let image: NSImage
    let pixels: CGSize
    let isFullSize: Bool
}

/// Key without activating Onecast, like the palette, so Escape reaches it and focus stays put.
private final class ClipboardImagePanel: NSPanel {
    private let imageView = NSImageView()

    init() {
        super.init(
            contentRect: .zero,
            styleMask: [.titled, .closable, .resizable, .fullSizeContentView, .nonactivatingPanel],
            backing: .buffered, defer: true)
        titlebarAppearsTransparent = true
        isMovableByWindowBackground = true
        isReleasedWhenClosed = false
        hidesOnDeactivate = false
        level = .floating
        animationBehavior = .documentWindow
        backgroundColor = .windowBackgroundColor
        imageView.imageScaling = .scaleProportionallyUpOrDown
        imageView.imageFrameStyle = .none
        contentView = imageView
        nameForAccessibility("clipboard.quickView", title: "Quick View")
    }

    override var canBecomeKey: Bool { true }

    func show(_ picture: Picture, title: String, on screen: NSScreen?) {
        imageView.image = picture.image
        self.title = title
        subtitle = "\(Int(picture.pixels.width)) × \(Int(picture.pixels.height))"
        setFrame(frame(fitting: picture.pixels, on: screen), display: false)
        makeKeyAndOrderFront(nil)
    }

    func replaceImage(_ image: NSImage) {
        imageView.image = image
    }

    /// Native size where it fits, otherwise scaled into most of the screen, centred on it.
    private func frame(fitting pixels: CGSize, on screen: NSScreen?) -> NSRect {
        let visible = screen?.visibleFrame ?? NSRect(x: 0, y: 0, width: 1280, height: 800)
        let scale = screen?.backingScaleFactor ?? 2
        let bounds = CGSize(width: visible.width * 0.85, height: visible.height * 0.85)
        var size = CGSize(width: pixels.width / scale, height: pixels.height / scale)
        let fit = min(1, bounds.width / max(size.width, 1), bounds.height / max(size.height, 1))
        size = CGSize(width: max(320, size.width * fit), height: max(200, size.height * fit))
        let content = NSRect(
            x: visible.midX - size.width / 2, y: visible.midY - size.height / 2,
            width: size.width, height: size.height)
        return frameRect(forContentRect: content)
    }

    override func cancelOperation(_ sender: Any?) { close() }

    /// Space closes it too, as it does Quick Look.
    override func keyDown(with event: NSEvent) {
        if event.charactersIgnoringModifiers == " " { close() } else { super.keyDown(with: event) }
    }

    override func resignKey() {
        super.resignKey()
        close()
    }

    /// A full-resolution bitmap can run past 100 MB, so it goes once the close animation has played.
    override func close() {
        super.close()
        DispatchQueue.main.asyncAfter(deadline: .now() + .milliseconds(400)) { [weak self] in
            guard let self, !isVisible else { return }
            imageView.image = nil
        }
    }
}
