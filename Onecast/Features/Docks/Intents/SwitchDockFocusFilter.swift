import AppIntents

/// A Docks setup, as the Focus filter's picker lists it.
struct DockSetupEntity: AppEntity {
    static let typeDisplayRepresentation: TypeDisplayRepresentation = "Dock Setup"
    static let defaultQuery = DockSetupQuery()

    let id: UUID
    let name: String

    var displayRepresentation: DisplayRepresentation { DisplayRepresentation(title: "\(name)") }
}

struct DockSetupQuery: EntityQuery {
    @MainActor
    func entities(for identifiers: [UUID]) async throws -> [DockSetupEntity] {
        Self.setups().filter { identifiers.contains($0.id) }
    }

    @MainActor
    func suggestedEntities() async throws -> [DockSetupEntity] {
        Self.setups()
    }

    @MainActor
    private static func setups() -> [DockSetupEntity] {
        AppCore.shared.docks.configuration.setups.map { DockSetupEntity(id: $0.id, name: $0.name) }
    }
}

/// Added under System Settings › Focus › Focus Filters; picks a setup as the Focus turns on.
struct SwitchDockFocusFilter: SetFocusFilterIntent {
    static let title: LocalizedStringResource = "Switch Dock"
    static let description = IntentDescription("Switches Onecast Docks to a setup while this Focus is on.")

    @Parameter(title: "Setup")
    var setup: DockSetupEntity?

    var displayRepresentation: DisplayRepresentation {
        DisplayRepresentation(title: "Switch Dock", subtitle: setup.map { "\($0.name)" })
    }

    /// Also runs when the Focus turns off, with no setup chosen: nothing is switched back then.
    @MainActor
    func perform() async throws -> some IntentResult {
        guard let setup else { return .result() }
        AppCore.shared.dockSwitchCoordinator.switchToSetup(id: setup.id)
        return .result()
    }
}
