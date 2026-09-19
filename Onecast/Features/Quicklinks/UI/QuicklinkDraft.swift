import Foundation

/// Editable state for one quicklink, shared by the Quicklinks pane's sheet and the launcher's
/// in-palette editor so both bind to the same fields and validation. Building the quicklink is here
/// too; only persistence (add vs update) and dismissal stay with each host.
@MainActor
@Observable
final class QuicklinkDraft {
    var name: String
    var link: String
    var iconSymbol: String?
    var openWithBundleID: String?
    var showsInRootSearch: Bool
    var isPinned: Bool
    /// Surfaced by the host when a save is refused; quicklinks are authored data, never dropped silently.
    var errorMessage: String?

    /// The quicklink being edited, kept so a save preserves its id, shortcut, favorite slot,
    /// visibility and trigger words — the editor never shows triggers, so it must carry them through.
    private let existing: Quicklink?

    var isEditing: Bool { existing != nil }
    var editingID: UUID? { existing?.id }
    var title: String { isEditing ? "Edit Quicklink" : "Add Quicklink" }

    init(quicklink: Quicklink?) {
        existing = quicklink
        name = quicklink?.name ?? ""
        link = quicklink?.link ?? ""
        iconSymbol = quicklink?.iconSymbol
        openWithBundleID = quicklink?.openWithBundleID
        showsInRootSearch = quicklink?.showsInRootSearch ?? true
        isPinned = quicklink?.isPinned ?? false
    }

    var trimmedName: String { name.trimmingCharacters(in: .whitespacesAndNewlines) }
    var trimmedLink: String { link.trimmingCharacters(in: .whitespacesAndNewlines) }
    var isValid: Bool { !trimmedName.isEmpty && !trimmedLink.isEmpty }

    /// The glyph a detected destination suggests, and what the icon picker's Automatic row shows.
    var automaticSymbol: String {
        QuicklinkDestination.detect(trimmedLink)?.defaultSymbol ?? Quicklink.sfSymbol
    }

    var resolvedSymbol: String { iconSymbol ?? automaticSymbol }

    func insert(_ token: String) {
        link += token
    }

    /// Editing keeps the UUID, and with it the quicklink's shortcut, favorite and visibility.
    func build() -> Quicklink {
        Quicklink(
            id: existing?.id ?? UUID(), name: name, link: link,
            openWithBundleID: openWithBundleID, iconSymbol: iconSymbol,
            // The row's checkbox owns Enabled; an edit carries the flag rather than resetting it.
            isEnabled: existing?.isEnabled ?? true,
            showsInRootSearch: showsInRootSearch,
            // Re-pinning keeps the original stamp, so saving an edit doesn't move the row.
            pinnedAt: isPinned ? (existing?.pinnedAt ?? Date()) : nil,
            createdAt: existing?.createdAt ?? Date(),
            // Triggers are edited in the Fallbacks pane, not here, so a save must not drop them.
            triggers: existing?.triggers ?? [])
    }
}
