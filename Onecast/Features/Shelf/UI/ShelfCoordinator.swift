import AppKit
import SwiftUI

/// Owns the one shelf: what it holds, its panel, and the drag shake that summons it.
@MainActor
@Observable
final class ShelfCoordinator {
    private(set) var groups: [ShelfGroup] = []
    /// The group opened to pick single items out of; nil shows every group.
    private(set) var openGroupID: UUID?
    private(set) var isTargeted = false
    private(set) var selection = ShelfSelection()

    @ObservationIgnored private unowned let core: AppCore
    @ObservationIgnored private var panel: ShelfPanel?
    @ObservationIgnored private let shakeMonitor = DragShakeMonitor()
    @ObservationIgnored private var sharePicker: NSSharingServicePicker?
    @ObservationIgnored private let tooltip = ShelfTooltip()

    init(core: AppCore) {
        self.core = core
        ShelfIntake.releaseLeftovers()
        shakeMonitor.onShake = { [weak self] in self?.show(at: NSEvent.mouseLocation, takingKey: false) }
    }

    var items: [ShelfItem] { groups.flatMap(\.items) }

    var openGroup: ShelfGroup? { groups.first { $0.id == openGroupID } }

    /// The rows on show: every group, or the open group's items.
    var rowIDs: [UUID] { openGroup?.items.map(\.id) ?? groups.map(\.id) }

    var selectedItems: [ShelfItem] { rowIDs.filter(selection.ids.contains).flatMap(items(forRow:)) }

    func isSelected(_ id: UUID) -> Bool { selection.ids.contains(id) }

    func press(_ id: UUID, _ modifiers: NSEvent.ModifierFlags) {
        selection.press(
            id, in: rowIDs, command: modifiers.contains(.command), shift: modifiers.contains(.shift))
    }

    func click(_ id: UUID) {
        selection.click(id)
    }

    func dragItems(from id: UUID) -> [ShelfItem] {
        selection.dragged(from: id, in: rowIDs).flatMap(items(forRow:))
    }

    func selectAll() {
        selection.selectAll(rowIDs)
    }

    private func items(forRow id: UUID) -> [ShelfItem] {
        if let group = groups.first(where: { $0.id == id }) { return group.items }
        return items.filter { $0.id == id }
    }

    var panelHeight: CGFloat {
        let rowCount = openGroup?.items.count ?? groups.count
        let rows = min(rowCount, Theme.Size.shelfVisibleRows)
        let body =
            groups.isEmpty
            ? Theme.Size.shelfDropZone
            : CGFloat(rows) * Theme.Size.shelfRow + Theme.Spacing.md * 2
        return Theme.Size.shelfHeader + body
    }

    func applyEnabled() {
        let settings = core.settings
        core.appIndex.setCommandsVisible([.showShelf], settings.shelfEnabled)
        if settings.shelfEnabled, settings.shelfShakeToOpen {
            shakeMonitor.start()
        } else {
            shakeMonitor.stop()
        }
        if !settings.shelfEnabled { close() }
    }

    func toggle() {
        if panel == nil { show(at: NSEvent.mouseLocation, takingKey: true) } else { close() }
    }

    /// A shake mid-drag must not take key from the app the drag started in.
    func show(at point: NSPoint, takingKey: Bool) {
        if let panel {
            panel.center(on: point)
            panel.orderFrontRegardless()
            if takingKey { panel.makeKey() }
            return
        }
        let panel = makePanel()
        self.panel = panel
        panel.center(on: point)
        panel.fadeIn(duration: Theme.Duration.enter) {
            if takingKey { panel.makeKeyAndOrderFront(nil) }
            panel.orderFrontRegardless()
        }
    }

    /// Every file moved onto the shelf goes back where it came from, so closing loses nothing.
    func close() {
        guard let closing = panel else { return }
        panel = nil
        closing.onKey = nil
        release(items)
        groups = []
        openGroupID = nil
        selection.clear()
        tooltip.hide()
        isTargeted = false
        closing.fadeOut(duration: Theme.Duration.exit)
    }

    /// A drop moves its files onto the shelf unless ⌥ asks to leave them where they are.
    func take(_ contents: [ShelfItem.Content], as groupID: UUID, moving: Bool) {
        add(
            as: groupID,
            contents.map { content in
                guard moving, case .file(let url) = content, let held = ShelfIntake.hold(url) else {
                    return ShelfItem(content)
                }
                return ShelfItem(.file(held), origin: url)
            })
    }

    /// A new drop shows every group again, so it is seen landing as one of its own.
    func add(as groupID: UUID, _ added: [ShelfItem]) {
        guard !added.isEmpty else { return }
        groups = ShelfStack.adding(added, as: groupID, to: groups)
        if openGroupID != groupID {
            openGroupID = nil
            selection.clear()
        }
        resize()
    }

    func openGroup(_ group: ShelfGroup) {
        guard group.items.count > 1 else {
            if let item = group.items.first { open(item) }
            return
        }
        openGroupID = group.id
        selection.clear()
        tooltip.hide()
        resize()
    }

    func closeGroup() {
        openGroupID = nil
        selection.clear()
        tooltip.hide()
        resize()
    }

    func remove(_ removed: [ShelfItem]) {
        release(removed)
        drop(removed)
    }

    func clear() {
        remove(items)
    }

    /// Esc drops the selection, then steps out of an open group, then closes the shelf.
    func handle(_ key: ShelfPanel.Key) {
        switch key {
        case .escape:
            if !selection.ids.isEmpty {
                selection.clear()
            } else if openGroupID != nil {
                closeGroup()
            } else {
                close()
            }
        case .selectAll: selectAll()
        case .delete: remove(selectedItems)
        }
    }

    private func drop(_ removed: [ShelfItem]) {
        groups = ShelfStack.removing(Set(removed.map(\.id)), from: groups)
        if openGroup == nil { openGroupID = nil }
        selection.keep(rowIDs)
        resize()
    }

    private func release(_ items: [ShelfItem]) {
        for item in items {
            if let url = item.fileURL { ShelfIntake.release(url, to: item.origin) }
        }
    }

    /// A move takes the rows with it at once: Finder moves asynchronously, so the file may not be gone yet.
    func dragEnded(_ dragged: [ShelfItem], operation: NSDragOperation) {
        let moved = operation.contains(.move) || operation.contains(.delete)
        let fileManager = FileManager.default
        let leaving = dragged.filter { item in
            moved || item.fileURL.map { !fileManager.fileExists(atPath: $0.path) } ?? false
        }
        guard !leaving.isEmpty else { return }
        drop(leaving)
        let files = leaving.compactMap(\.fileURL)
        Task {
            // Long enough for Finder to finish a large move before its holding folder is tidied.
            for _ in 0..<60 where files.contains(where: { fileManager.fileExists(atPath: $0.path) }) {
                try? await Task.sleep(for: .seconds(1))
            }
            files.forEach(ShelfIntake.discardEmptyFolder)
        }
    }

    func open(_ item: ShelfItem) {
        switch item.content {
        case .file(let url), .link(let url): NSWorkspace.shared.open(url)
        case .text: copy([item])
        }
    }

    func reveal(_ items: [ShelfItem]) {
        let files = items.compactMap(\.fileURL)
        guard !files.isEmpty else { return }
        NSWorkspace.shared.activateFileViewerSelecting(files)
    }

    func copy(_ items: [ShelfItem]) {
        guard !items.isEmpty else { return }
        let pasteboard = NSPasteboard.general
        pasteboard.clearContents()
        pasteboard.writeObjects(items.map(Self.writer))
        core.showMessage(items.count == 1 ? "Copied" : "Copied \(items.count) items")
    }

    func share(_ items: [ShelfItem]) {
        guard !items.isEmpty, let anchor = panel?.contentView else { return }
        let picker = NSSharingServicePicker(items: items.map(Self.writer))
        sharePicker = picker
        picker.show(
            relativeTo: CGRect(
                x: anchor.bounds.maxX, y: anchor.bounds.maxY - Theme.Size.shelfHeader / 2, width: 0, height: 0
            ),
            of: anchor, preferredEdge: .maxX)
    }

    /// A group of one acts as its item; a larger one opens to show what is in it.
    private func menu(for group: ShelfGroup, opens: Bool = true) -> NSMenu {
        let items = group.items
        let menu = NSMenu()
        if opens, items.count > 1 {
            menu.addItem(
                ShelfMenuItem("Show Items", symbol: "rectangle.stack") { [weak self] in self?.openGroup(group) })
        } else {
            menu.addItem(
                ShelfMenuItem("Open", symbol: "arrow.up.forward.app") { [weak self] in
                    items.forEach { self?.open($0) }
                })
        }
        if items.contains(where: { $0.fileURL != nil }) {
            menu.addItem(
                ShelfMenuItem("Show in Finder", symbol: "folder") { [weak self] in self?.reveal(items) })
        }
        menu.addItem(ShelfMenuItem("Copy", symbol: "doc.on.doc") { [weak self] in self?.copy(items) })
        menu.addItem(
            ShelfMenuItem("Share…", symbol: "square.and.arrow.up") { [weak self] in self?.share(items) })
        menu.addItem(.separator())
        menu.addItem(
            ShelfMenuItem("Remove from Shelf", symbol: "minus.circle") { [weak self] in self?.remove(items) })
        return menu
    }

    /// A row inside a larger selection acts on the whole selection.
    func menu(forRow id: UUID) -> NSMenu {
        if isSelected(id), selection.ids.count > 1 {
            return menu(for: ShelfGroup(id: UUID(), items: selectedItems), opens: false)
        }
        if let group = groups.first(where: { $0.id == id }) { return menu(for: group) }
        return menu(for: ShelfGroup(id: id, items: items(forRow: id)), opens: false)
    }

    private static func writer(_ item: ShelfItem) -> any NSPasteboardWriting {
        switch item.content {
        case .file(let url), .link(let url): url as NSURL
        case .text(let text): text as NSString
        }
    }

    private func resize() {
        panel?.setHeight(panelHeight)
    }

    private func makePanel() -> ShelfPanel {
        let hosting = NSHostingView(rootView: ShelfView(coordinator: self, tooltips: nil))
        hosting.rootView = ShelfView(coordinator: self, tooltips: tooltip.presenter(in: hosting))
        hosting.setFrameSize(NSSize(width: Theme.Size.shelfWidth, height: panelHeight))
        let drop = ShelfDropView(content: hosting)
        drop.onTargeted = { [weak self] targeted in
            guard let self, isTargeted != targeted else { return }
            isTargeted = targeted
        }
        drop.onDrop = { [weak self] pasteboard, moving in
            guard let self else { return false }
            let groupID = UUID()
            let contents = ShelfIntake.read(pasteboard) { [weak self] in
                self?.add(as: groupID, $0.map { ShelfItem($0) })
            }
            take(contents, as: groupID, moving: moving)
            return true
        }
        let panel = ShelfPanel(content: drop)
        panel.onKey = { [weak self] in self?.handle($0) }
        return panel
    }
}
