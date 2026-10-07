import AppKit

/// What a click, a drop or a menu row does with a dock's items: the funnel into the rest of
/// Onecast, so the surface never reaches for `NSWorkspace` or another coordinator itself.
@MainActor
final class DockItemActions {
    private unowned let core: AppCore

    init(core: AppCore) {
        self.core = core
    }

    // MARK: - Apps

    /// Where the app is now: its recorded path, else wherever its bundle ID lives.
    func resolvedURL(for reference: DockAppReference) -> URL? {
        if FileManager.default.fileExists(atPath: reference.path) {
            return URL(fileURLWithPath: reference.path)
        }
        return reference.bundleID.flatMap {
            NSWorkspace.shared.urlForApplication(withBundleIdentifier: $0)
        }
    }

    /// Launch it or bring it forward; a click on the app already in front minimizes its window
    /// when the dock asks for that.
    func activate(
        _ reference: DockAppReference, running: DockRunningApp?, minimizesWhenFocused: Bool
    ) {
        if let running, running.isActive, minimizesWhenFocused, let bundleID = running.bundleID,
            core.dockCoordinator.windows.minimizeFocusedWindow(of: bundleID)
        {
            return
        }
        guard let url = resolvedURL(for: reference) ?? running.map({ URL(fileURLWithPath: $0.path) })
        else {
            core.showMessage("Can't find \(Self.name(of: reference))", tone: .danger)
            return
        }
        AppLauncher.launch(url)
    }

    func activate(_ app: DockRunningApp, minimizesWhenFocused: Bool) {
        activate(
            DockAppReference(bundleID: app.bundleID, path: app.path), running: app,
            minimizesWhenFocused: minimizesWhenFocused)
    }

    func quit(bundleID: String) {
        AppLauncher.quit(bundleID: bundleID)
    }

    /// A document dropped on an app's tile opens in that app.
    func open(_ urls: [URL], with reference: DockAppReference) {
        guard let appURL = resolvedURL(for: reference) else {
            core.showMessage("Can't find \(Self.name(of: reference))", tone: .danger)
            return
        }
        Task {
            do {
                _ = try await NSWorkspace.shared.open(
                    urls, withApplicationAt: appURL, configuration: NSWorkspace.OpenConfiguration())
            } catch {
                core.showMessage("\(Self.name(of: reference)) couldn't open that", tone: .danger)
            }
        }
    }

    // MARK: - Files, folders, links

    func open(path: String) {
        let url = URL(fileURLWithPath: path)
        guard FileManager.default.fileExists(atPath: path) else {
            core.showMessage("Can't find \(url.lastPathComponent)", tone: .danger)
            return
        }
        AppLauncher.open(url)
    }

    func showInFinder(path: String) {
        AppLauncher.showInFinder(URL(fileURLWithPath: path))
    }

    func open(link: DockLinkReference) {
        guard let url = URL(string: link.url) else {
            core.showMessage("“\(link.title)” isn't a valid link", tone: .danger)
            return
        }
        AppLauncher.open(url)
    }

    /// Through the Apple Shortcuts coordinator, so its feature switch still gates the run.
    func runShortcut(named name: String) {
        guard core.settings.appleShortcutsEnabled else {
            core.showMessage("Turn on Apple Shortcuts in Settings to run “\(name)”", tone: .danger)
            return
        }
        let match = core.appleShortcutCoordinator.entries.first {
            $0.name.localizedCaseInsensitiveCompare(name) == .orderedSame
        }
        guard let id = match.flatMap({ AppleShortcut.id(fromEntryID: $0.id) }) else {
            core.showMessage("No shortcut named “\(name)”", tone: .danger)
            return
        }
        core.appleShortcutCoordinator.run(id: id)
    }

    // MARK: - Trash

    func openTrash() {
        core.systemActionCoordinator.runSystemAction(id: .openTrash)
    }

    func emptyTrash() {
        core.systemActionCoordinator.runSystemAction(id: .emptyTrash)
    }

    /// Files dropped on the Trash tile move there, as Finder's own drop does.
    func moveToTrash(_ urls: [URL]) {
        let files = urls.filter(\.isFileURL)
        guard !files.isEmpty else { return }
        Task {
            let failed = await Task.detached(priority: .userInitiated) {
                Self.trash(files)
            }.value
            if failed.isEmpty {
                core.showMessage(files.count == 1 ? "Moved to Trash" : "Moved \(files.count) to Trash")
            } else {
                core.showMessage("Couldn't move \(failed[0]) to Trash", tone: .danger)
            }
        }
    }

    /// The names that would not go, in the order tried.
    nonisolated private static func trash(_ urls: [URL]) -> [String] {
        urls.compactMap { url in
            do {
                try FileManager.default.trashItem(at: url, resultingItemURL: nil)
                return nil
            } catch {
                return url.lastPathComponent
            }
        }
    }

    // MARK: - Names and artwork

    static func name(of reference: DockAppReference) -> String {
        Bundle(path: reference.path)?.installedAppName
            ?? URL(fileURLWithPath: reference.path).deletingPathExtension().lastPathComponent
    }

    func name(of item: DockItem) -> String? {
        switch item.kind {
        case .app(let reference):
            let current = resolvedURL(for: reference).map {
                DockAppReference(bundleID: reference.bundleID, path: $0.path)
            }
            return Self.name(of: current ?? reference)
        case .folder(let folder):
            return folder.customName ?? FileManager.default.displayName(atPath: folder.path)
        case .file(let path):
            return FileManager.default.displayName(atPath: path)
        case .link(let link):
            return link.title
        case .shortcut(let name):
            return name
        case .widget(let widget):
            return core.dockCoordinator.widgets.descriptor(id: widget.widgetID)?.metadata.name
        case .spacer:
            return nil
        }
    }

    /// The picture that follows the pointer when a tile is dragged.
    func dragImage(for item: DockItem, side: CGFloat) -> NSImage {
        let source: NSImage
        switch item.kind {
        case .app(let reference):
            if let custom = reference.customIcon {
                source = IconCache.icon(for: custom.entryIcon, fileURL: URL(fileURLWithPath: reference.path))
            } else {
                source = IconCache.icon(forFile: resolvedURL(for: reference)?.path ?? reference.path)
            }
        case .folder(let folder):
            source = IconCache.icon(forFile: folder.path)
        case .file(let path):
            source = IconCache.icon(forFile: path)
        case .link(let link):
            source = IconCache.symbolIcon(named: link.symbol ?? "globe")
        case .shortcut:
            source = IconCache.icon(forFile: AppleShortcutCoordinator.applicationURL.path)
        case .widget:
            source = IconCache.symbolIcon(named: "square.grid.2x2")
        case .spacer:
            source = IconCache.symbolIcon(named: "rectangle.dashed")
        }
        guard let image = source.copy() as? NSImage else { return source }
        image.size = NSSize(width: side, height: side)
        return image
    }
}
