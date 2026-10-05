import Foundation

/// The Docks library: every custom dock, saved macOS Dock layout and setup, as one value.
@MainActor
@Observable
final class DockStore {
    private static let defaultsKey = "docks"

    private let defaults: UserDefaults
    private(set) var configuration: DockConfiguration
    @ObservationIgnored var onChange: ((DockConfiguration) -> Void)?

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        let decoded =
            defaults.data(forKey: Self.defaultsKey)
            .flatMap { try? JSONDecoder().decode(DockConfiguration.self, from: $0) }
            ?? DockConfiguration()
        var cleaned = decoded
        cleaned.sanitize()
        configuration = cleaned
        if cleaned != decoded { persist() }
    }

    var docks: [CustomDock] { configuration.docks }

    func dock(id: UUID) -> CustomDock? {
        configuration.docks.first { $0.id == id }
    }

    func setup(id: UUID) -> DockSetup? {
        configuration.setups.first { $0.id == id }
    }

    func nativeLayout(id: UUID) -> NativeDockLayout? {
        configuration.nativeLayouts.first { $0.id == id }
    }

    /// The one write path: every edit is a transform, sanitized before it lands.
    func update(_ transform: (inout DockConfiguration) -> Void) {
        var updated = configuration
        transform(&updated)
        updated.sanitize()
        guard updated != configuration else { return }
        configuration = updated
        persist()
        onChange?(updated)
    }

    func updateDock(id: UUID, _ transform: (inout CustomDock) -> Void) {
        update { configuration in
            guard let index = configuration.docks.firstIndex(where: { $0.id == id }) else { return }
            transform(&configuration.docks[index])
        }
    }

    func updateLayout(dockID: UUID, layoutID: UUID, _ transform: (inout DockLayout) -> Void) {
        updateDock(id: dockID) { dock in
            guard let index = dock.layouts.firstIndex(where: { $0.id == layoutID }) else { return }
            transform(&dock.layouts[index])
        }
    }

    @discardableResult
    func addDock(_ dock: CustomDock) -> CustomDock {
        var value = dock
        value.name = Self.uniqueName(value.name, among: configuration.docks.map(\.name))
        update { $0.docks.append(value) }
        return value
    }

    func removeDock(id: UUID) {
        update { $0.docks.removeAll { $0.id == id } }
    }

    /// A copy takes fresh identities throughout, so no widget instance is shared with the original.
    @discardableResult
    func duplicateDock(id: UUID) -> CustomDock? {
        guard let original = dock(id: id) else { return nil }
        let layouts = original.layouts.map { layout in
            DockLayout(name: layout.name, color: layout.color, items: layout.items.map(\.copy))
        }
        let active = original.layouts.firstIndex { $0.id == original.activeLayoutID } ?? 0
        var copy = CustomDock(
            name: original.name + " Copy", isVisible: false, placement: original.placement,
            appearance: original.appearance, content: original.content, layouts: layouts)
        copy.activeLayoutID = layouts[active].id
        return addDock(copy)
    }

    func activateLayout(dockID: UUID, layoutID: UUID) {
        updateDock(id: dockID) { $0.activeLayoutID = layoutID }
    }

    /// Moves a dock one layout along its own list, wrapping; returns the layout now shown.
    @discardableResult
    func stepLayout(dockID: UUID, by offset: Int) -> DockLayout? {
        guard let dock = dock(id: dockID), dock.layouts.count > 1 else { return nil }
        let next = dock.layout(steppedBy: offset)
        activateLayout(dockID: dockID, layoutID: next.id)
        return next
    }

    /// Marks a setup active and applies its custom-dock half; the native half is the caller's.
    func activateSetup(id: UUID) {
        guard let setup = setup(id: id) else { return }
        update { configuration in
            configuration.activeSetupID = id
            for state in setup.docks {
                guard let index = configuration.docks.firstIndex(where: { $0.id == state.dockID })
                else { continue }
                configuration.docks[index].isVisible = state.isVisible
                if let layoutID = state.layoutID {
                    configuration.docks[index].activeLayoutID = layoutID
                }
            }
            if let native = setup.nativeLayoutID { configuration.activeNativeLayoutID = native }
        }
    }

    /// Replaces the whole library on backup import, cleaning rather than rejecting.
    func replace(with incoming: DockConfiguration) {
        update { $0 = incoming }
    }

    private func persist() {
        guard let data = try? JSONEncoder().encode(configuration) else { return }
        defaults.set(data, forKey: Self.defaultsKey)
    }

    /// "Dock" → "Dock 2" → "Dock 3", so a new dock is always told apart in menus.
    static func uniqueName(_ name: String, among existing: [String]) -> String {
        let base = name.trimmingCharacters(in: .whitespacesAndNewlines)
        let taken = Set(existing.map { $0.lowercased() })
        guard taken.contains(base.lowercased()) else { return base }
        var index = 2
        while taken.contains("\(base) \(index)".lowercased()) { index += 1 }
        return "\(base) \(index)"
    }
}
