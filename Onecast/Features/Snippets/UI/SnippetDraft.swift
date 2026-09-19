import Foundation

/// Editable state for one snippet, shared by the Snippets pane's sheet and the launcher's in-palette
/// editor so both bind to the same fields and validation. Building the snippet is here too; only
/// persistence (create vs save) and dismissal stay with each host.
@MainActor
@Observable
final class SnippetDraft {
    var name: String
    var keyword: String
    var text: String
    var isEnabled: Bool
    var showsConfirmation: Bool
    /// Surfaced by the host when a save is refused — a revision conflict or a write failure.
    var errorMessage: String?

    /// The record being edited, kept so a save targets its file and revision; nil on add.
    private let record: StoredSnippet?

    var isEditing: Bool { record != nil }
    var editingRecord: StoredSnippet? { record }
    var title: String { isEditing ? "Edit Snippet" : "Add Snippet" }

    init(record: StoredSnippet?) {
        self.record = record
        let snippet = record?.snippet
        name = snippet?.name ?? ""
        keyword = snippet?.keyword ?? ""
        text = snippet?.text ?? ""
        isEnabled = snippet?.isEnabled ?? true
        showsConfirmation = snippet?.showsConfirmation ?? false
    }

    var trimmedName: String { name.trimmingCharacters(in: .whitespacesAndNewlines) }
    var isValid: Bool { !trimmedName.isEmpty }

    func build() -> Snippet {
        Snippet(
            name: trimmedName,
            text: text,
            keyword: trimmedOrNil(keyword),
            isEnabled: isEnabled,
            showsConfirmation: showsConfirmation)
    }

    private func trimmedOrNil(_ value: String) -> String? {
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }
}
