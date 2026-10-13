import Foundation
import Observation

/// The Create Event form's transient state: the draft and which control holds focus.
@MainActor
@Observable
final class EventEditorSession {
    enum Field: CaseIterable, Hashable {
        case title, start, duration
    }

    var draft = EventDraft()
    var focusedField: Field = .title

    /// ⇥ / ⇧⇥ wrap at either end, so focus never leaves the form.
    func advanceFocus(backwards: Bool) {
        let fields = Field.allCases
        let index = fields.firstIndex(of: focusedField) ?? 0
        focusedField = fields[(index + (backwards ? fields.count - 1 : 1)) % fields.count]
    }
}
