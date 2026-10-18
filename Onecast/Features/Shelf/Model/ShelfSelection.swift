import Foundation

/// Finder's list selection: click picks one, ⌘ toggles, ⇧ takes the run from the last pick.
struct ShelfSelection: Equatable {
    private(set) var ids: Set<UUID> = []
    private var anchor: UUID?
    /// A plain press on a selected row keeps the rest for a drag; only a click narrows to it.
    private var narrowing: UUID?

    mutating func press(_ id: UUID, in order: [UUID], command: Bool, shift: Bool) {
        narrowing = nil
        if command {
            if ids.contains(id) { ids.remove(id) } else { ids.insert(id) }
            anchor = id
        } else if shift, let anchor, let from = order.firstIndex(of: anchor),
            let to = order.firstIndex(of: id)
        {
            ids = Set(order[min(from, to)...max(from, to)])
        } else if ids.contains(id) {
            narrowing = id
        } else {
            ids = [id]
            anchor = id
        }
    }

    mutating func click(_ id: UUID) {
        guard narrowing == id else { return }
        narrowing = nil
        ids = [id]
        anchor = id
    }

    mutating func selectAll(_ order: [UUID]) {
        ids = Set(order)
        anchor = order.first
    }

    mutating func clear() {
        self = ShelfSelection()
    }

    /// Forgets rows that are gone.
    mutating func keep(_ order: [UUID]) {
        ids.formIntersection(order)
        if let anchor, !order.contains(anchor) { self.anchor = nil }
    }

    /// A drag from a selected row takes the whole selection, in shelf order; any other drags alone.
    func dragged(from id: UUID, in order: [UUID]) -> [UUID] {
        ids.contains(id) ? order.filter(ids.contains) : [id]
    }
}
