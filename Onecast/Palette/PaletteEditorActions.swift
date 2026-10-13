import Foundation

extension AppCore {
    /// Every editor closes through its own coordinator, so each one keeps its draft rules.
    func cancelOpenEditor() -> Bool {
        switch palette.mode {
        case .quicklinkEditor: quicklinkCoordinator.cancelQuicklinkEditing()
        case .snippetEditor: snippetCoordinator.cancelSnippetEditing()
        case .schedulerEditor: schedulerEditorCoordinator.cancelSchedulerEditing()
        case .eventEditor: calendarCoordinator.cancelEventEditing()
        case .customCommandEditor: customCommandCoordinator.cancelCustomCommandEditing()
        default: return false
        }
        return true
    }

    /// ⌘↵ saves from every field, including the multi-line ones that keep a bare ↵ for newlines.
    func saveOpenEditor() -> Bool {
        switch palette.mode {
        case .quicklinkEditor: quicklinkCoordinator.saveEditor()
        case .snippetEditor: snippetCoordinator.saveEditor()
        case .schedulerEditor: schedulerEditorCoordinator.save()
        case .eventEditor: calendarCoordinator.saveEvent()
        case .customCommandEditor: customCommandCoordinator.saveCustomCommand()
        default: return false
        }
        return true
    }
}
