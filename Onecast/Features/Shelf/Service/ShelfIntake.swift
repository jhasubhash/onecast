import AppKit
import UniformTypeIdentifiers

/// Turns a dropped pasteboard into shelf contents, keeping only the richest form it offers.
@MainActor
enum ShelfIntake {
    static let draggedTypes: [NSPasteboard.PasteboardType] =
        [.fileURL, .URL, .png, .tiff, .string]
        + NSFilePromiseReceiver.readableDraggedTypes.map { NSPasteboard.PasteboardType($0) }

    /// Where moved files, promised files and dropped images wait while the shelf holds them.
    static var holdingFolder: URL {
        AppPaths.caches().appending(path: "Shelf", directoryHint: .isDirectory)
    }

    /// Files, then promised files, images, links and text; promises arrive later through `deliver`.
    static func read(
        _ pasteboard: NSPasteboard, deliver: @escaping @MainActor ([ShelfItem.Content]) -> Void
    ) -> [ShelfItem.Content] {
        let files = PasteboardFiles.urls(on: pasteboard)
        if !files.isEmpty { return files.map(ShelfItem.Content.file) }
        let promises =
            pasteboard.readObjects(forClasses: [NSFilePromiseReceiver.self]) as? [NSFilePromiseReceiver]
            ?? []
        if !promises.isEmpty {
            receive(promises, deliver: deliver)
            return []
        }
        if let image = imageFile(from: pasteboard) { return [.file(image)] }
        let links = (pasteboard.readObjects(forClasses: [NSURL.self]) as? [URL] ?? [])
            .filter { !$0.isFileURL }
        if !links.isEmpty { return links.map(ShelfItem.Content.link) }
        guard let text = pasteboard.string(forType: .string),
            !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        else { return [] }
        if let url = URL(string: text.trimmingCharacters(in: .whitespacesAndNewlines)),
            let scheme = url.scheme, ["http", "https"].contains(scheme), url.host() != nil
        {
            return [.link(url)]
        }
        return [.text(text)]
    }

    static func isHeld(_ url: URL) -> Bool {
        url.standardizedFileURL.path.hasPrefix(holdingFolder.standardizedFileURL.path + "/")
    }

    /// Moves a file onto the shelf; nil leaves it where it is, as for one on another volume.
    static func hold(_ url: URL) -> URL? {
        guard !isHeld(url), sameVolume(url, holdingFolder.deletingLastPathComponent()),
            let folder = freshFolder()
        else { return nil }
        let held = folder.appending(path: url.lastPathComponent)
        do {
            try FileManager.default.moveItem(at: url, to: held)
        } catch {
            try? FileManager.default.removeItem(at: folder)
            return nil
        }
        // Beside the file rather than on it, so nothing of the shelf's leaves with the file.
        try? url.path.write(to: originNote(for: folder), atomically: true, encoding: .utf8)
        return held
    }

    /// Puts a held file back where it came from; one the shelf made itself has nowhere to go.
    static func release(_ url: URL, to origin: URL?) {
        guard isHeld(url) else { return }
        let fileManager = FileManager.default
        let folder = url.deletingLastPathComponent()
        if let origin {
            var home = origin
            if !fileManager.fileExists(atPath: origin.deletingLastPathComponent().path) {
                home = fileManager.homeDirectoryForCurrentUser
                    .appending(path: "Downloads", directoryHint: .isDirectory)
                    .appending(path: origin.lastPathComponent)
            }
            let destination = ShelfReturn.destination(for: home) { fileManager.fileExists(atPath: $0.path) }
            guard (try? fileManager.moveItem(at: url, to: destination)) != nil else { return }
        } else {
            try? fileManager.removeItem(at: url)
        }
        discard(folder)
    }

    /// Finder took a held file away, so the folder that held it goes too.
    static func discardEmptyFolder(of url: URL) {
        let folder = url.deletingLastPathComponent()
        guard isHeld(url),
            (try? FileManager.default.contentsOfDirectory(atPath: folder.path))?.isEmpty == true
        else { return }
        discard(folder)
    }

    /// A launch after a crash returns whatever the last one still held.
    static func releaseLeftovers() {
        let fileManager = FileManager.default
        let entries =
            (try? fileManager.contentsOfDirectory(at: holdingFolder, includingPropertiesForKeys: nil)) ?? []
        for folder in entries where folder.hasDirectoryPath {
            let files =
                (try? fileManager.contentsOfDirectory(at: folder, includingPropertiesForKeys: nil)) ?? []
            let origin = (try? String(contentsOf: originNote(for: folder), encoding: .utf8))
                .map { URL(fileURLWithPath: $0) }
            files.forEach { release($0, to: origin) }
            if files.isEmpty { discard(folder) }
        }
    }

    private static func originNote(for folder: URL) -> URL {
        folder.deletingLastPathComponent().appending(path: folder.lastPathComponent + ".origin")
    }

    private static func discard(_ folder: URL) {
        try? FileManager.default.removeItem(at: folder)
        try? FileManager.default.removeItem(at: originNote(for: folder))
    }

    private static func sameVolume(_ first: URL, _ second: URL) -> Bool {
        let key = URLResourceKey.volumeIdentifierKey
        guard let one = try? first.resourceValues(forKeys: [key]).volumeIdentifier,
            let two = try? second.resourceValues(forKeys: [key]).volumeIdentifier
        else { return false }
        return one.isEqual(two)
    }

    private static func freshFolder() -> URL? {
        let folder = holdingFolder.appending(path: UUID().uuidString, directoryHint: .isDirectory)
        do {
            try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
            return folder
        } catch {
            return nil
        }
    }

    private static let promiseQueue: OperationQueue = {
        let queue = OperationQueue()
        queue.qualityOfService = .userInitiated
        return queue
    }()

    private static func receive(
        _ promises: [NSFilePromiseReceiver],
        deliver: @escaping @MainActor ([ShelfItem.Content]) -> Void
    ) {
        for promise in promises {
            guard let folder = freshFolder() else { continue }
            promise.receivePromisedFiles(
                atDestination: folder, options: [:], operationQueue: promiseQueue
            ) { url, error in
                guard error == nil else { return }
                Task { @MainActor in deliver([.file(url)]) }
            }
        }
    }

    /// A browser's image drag carries pixels without a file, so they are saved as a PNG to hold.
    private static func imageFile(from pasteboard: NSPasteboard) -> URL? {
        let png =
            pasteboard.data(forType: .png)
            ?? pasteboard.data(forType: .tiff).flatMap {
                NSBitmapImageRep(data: $0)?.representation(using: .png, properties: [:])
            }
        guard let png, let folder = freshFolder() else { return nil }
        let url = folder.appending(path: "Image.png", directoryHint: .notDirectory)
        do {
            try png.write(to: url)
            return url
        } catch {
            return nil
        }
    }
}
