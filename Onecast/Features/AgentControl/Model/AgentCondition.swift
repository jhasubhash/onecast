import Foundation

/// What `waitFor` (or any action's `until`) waits on; every field set must hold at once.
struct AgentCondition: Equatable, Sendable {
    var visible: Bool?
    var mode: String?
    var query: String?
    var selection: Int?
    var minimumRows: Int?
    /// Some element in `window` (or in any window) shows this text, case-insensitively.
    var text: String?
    var absentText: String?
    var window: String?
    var absentWindow: String?

    var isEmpty: Bool { self == AgentCondition() }

    init(
        visible: Bool? = nil, mode: String? = nil, query: String? = nil, selection: Int? = nil,
        minimumRows: Int? = nil, text: String? = nil, absentText: String? = nil,
        window: String? = nil, absentWindow: String? = nil
    ) {
        self.visible = visible
        self.mode = mode
        self.query = query
        self.selection = selection
        self.minimumRows = minimumRows
        self.text = text
        self.absentText = absentText
        self.window = window
        self.absentWindow = absentWindow
    }

    init(_ arguments: AgentCommand.Arguments) throws {
        self.init(
            visible: try arguments.optional("visible"), mode: try arguments.optional("mode"),
            query: try arguments.optional("query"), selection: try arguments.optional("selection"),
            minimumRows: try arguments.optional("minimumRows"), text: try arguments.optional("text"),
            absentText: try arguments.optional("absentText"),
            window: try arguments.optional("window"),
            absentWindow: try arguments.optional("absentWindow"))
    }

    /// Rows and text come from element trees; everything else from the palette alone.
    var needsElements: Bool { text != nil || absentText != nil || minimumRows != nil }

    func isMet(by snapshot: AgentSnapshot) -> Bool {
        let palette = snapshot.palette
        if let visible, palette.visible != visible { return false }
        if let mode, palette.mode != mode { return false }
        if let query, palette.query != query { return false }
        if let selection, palette.selection != selection { return false }
        if let minimumRows, (palette.rows?.count ?? 0) < minimumRows { return false }
        let windowIDs = Set(snapshot.windows.map(\.id))
        if let absentWindow, windowIDs.contains(absentWindow) { return false }
        if let window, !windowIDs.contains(window) { return false }
        let scope = snapshot.windows.filter { window == nil || $0.id == window }
        let shows: (String) -> Bool = { text in
            scope.contains { ($0.elements ?? []).contains { $0.contains(text: text) } }
        }
        if let text, !shows(text) { return false }
        if let absentText, shows(absentText) { return false }
        return true
    }

    /// What a timeout reports, so the reader sees which wish went unmet.
    var summary: String {
        let parts: [String?] = [
            visible.map { "visible=\($0)" }, mode.map { "mode=\($0)" }, query.map { "query=\"\($0)\"" },
            selection.map { "selection=\($0)" }, minimumRows.map { "rows>=\($0)" },
            text.map { "text \"\($0)\"" }, absentText.map { "no text \"\($0)\"" },
            window.map { "window \($0)" }, absentWindow.map { "no window \($0)" },
        ]
        return parts.compactMap(\.self).joined(separator: ", ")
    }
}
