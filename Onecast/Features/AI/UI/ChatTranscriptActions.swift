import SwiftUI

/// What a transcript's controls do, supplied by the surface that shows it; nil hides the control.
struct ChatTranscriptActions {
    /// A reply's ```choices``` button answers with its own text.
    var choose: ((String) -> Void)?
    var regenerate: (() -> Void)?
}

extension EnvironmentValues {
    @Entry var chatTranscriptActions = ChatTranscriptActions()
    @Entry var chatFindHighlight: ChatFindHighlight?
}
