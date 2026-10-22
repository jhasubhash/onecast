import AppKit
import QuickLookUI

/// The system Quick Look panel for one clipboard image, key without taking focus from the app.
@MainActor
final class ClipboardQuickLook: NSObject, QLPreviewPanelDataSource, QLPreviewPanelDelegate {
    private var item: PreviewItem?

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

    /// `title` stands in for a held image's file name, which is only a UUID.
    func show(_ url: URL, title: String) {
        item = PreviewItem(previewItemURL: url, previewItemTitle: title)
        guard let panel = QLPreviewPanel.shared() else { return }
        // Like the palette: an accessory app's activation can be refused, a key panel's never is.
        panel.styleMask.insert(.nonactivatingPanel)
        panel.dataSource = self
        panel.delegate = self
        panel.reloadData()
        panel.currentPreviewItemIndex = 0
        panel.makeKeyAndOrderFront(nil)
    }

    nonisolated func numberOfPreviewItems(in panel: QLPreviewPanel?) -> Int {
        MainActor.assumeIsolated { item == nil ? 0 : 1 }
    }

    nonisolated func previewPanel(
        _ panel: QLPreviewPanel?, previewItemAt index: Int
    ) -> (any QLPreviewItem)? {
        MainActor.assumeIsolated { item }
    }

    nonisolated func windowWillClose(_ notification: Notification) {
        MainActor.assumeIsolated { item = nil }
    }
}

private final class PreviewItem: NSObject, QLPreviewItem, Sendable {
    let previewItemURL: URL?
    let previewItemTitle: String?

    init(previewItemURL: URL, previewItemTitle: String) {
        self.previewItemURL = previewItemURL
        self.previewItemTitle = previewItemTitle
    }
}
