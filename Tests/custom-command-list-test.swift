import Observation
import SwiftUI
import Synchronization

@main
@MainActor
struct CustomCommandListTests {
    static var failures = 0
    static var passes = 0

    static func main() async throws {
        let suite = "custom-command-list-test.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suite)!
        defer { defaults.removePersistentDomain(forName: suite) }
        let store = CustomCommandStore(defaults: defaults)
        let coordinator = CustomCommandCoordinator()
        let vm = PaletteState()
        func screen() -> CustomCommandListScreen {
            CustomCommandListScreen(
                store: store, coordinator: coordinator, vm: vm,
                metrics: InterfaceMetrics(), openActions: {})
        }

        let empty = screen()
        expect(empty.rows.isEmpty, "an empty library has no rows")
        expect(empty.primaryActionTitle == "Create Custom Command", "empty libraries offer creation")
        _ = empty.body(selection: 0, scroll: ScrollIntent())
        expect(EmptyResults.lastText == "No custom commands yet", "an empty library has its own message")
        empty.activate(at: 0)
        expect(coordinator.editRequests == [nil], "activating an empty library creates a command")

        let first = try store.add(CustomCommand(name: "Alpha", command: "alpha"))
        let second = try store.add(
            CustomCommand(name: "Beta", command: "beta", showsInRootSearch: false))
        _ = try store.add(CustomCommand(name: "Disabled", command: "disabled", isEnabled: false))
        let full = screen()
        expect(full.rows.map(\.id) == [first.id, second.id], "only enabled commands are browsable")
        expect(full.primaryActionTitle == "Run Command", "a populated library offers Run")
        expect(full.actions(at: 1)?.header == second.name, "actions address the rendered row")
        expect(
            full.actions(at: 1)?.items.map(\.title) == [
                "Run Command", "Edit Custom Command", "Create Custom Command",
                "Delete Custom Command"
            ], "a row offers run, edit, create and delete")
        full.actions(at: 0)?.items.first?.action()
        expect(coordinator.ran == first.id, "the menu's Run addresses the rendered row")
        full.activate(at: 1)
        expect(coordinator.ran == second.id, "activation addresses the rendered row")
        expect(full.perform(.edit, at: 1), "the snapshot supports editing")
        expect(coordinator.editRequests.last == second.id, "editing addresses the rendered row")
        expect(full.perform(.newItem, at: 1), "a selected row still creates")
        expect(coordinator.editRequests.last == .some(nil), "creating opens an empty editor")
        expect(full.perform(.commandDelete, at: 0), "the snapshot supports deleting")
        for _ in 0..<5 where coordinator.deleted == nil { await Task.yield() }
        expect(coordinator.deleted == first.id, "deleting addresses the rendered row")
        expect(
            full.actions(at: full.rows.count)?.items.map(\.title) == ["Create Custom Command"],
            "no selection offers only creation")

        vm.query = "Alpha"
        let filtered = screen()
        vm.query = "Beta"
        expect(filtered.rows.map(\.id) == [first.id], "one screen keeps one result snapshot")
        expect(
            filtered.actions(at: 0)?.header == first.name,
            "repeated reads do not refilter the snapshot")
        expect(screen().rows.map(\.id) == [second.id], "a new screen picks up the current query")

        let changed = Mutex(false)
        withObservationTracking {
            _ = screen()
        } onChange: {
            changed.withLock { $0 = true }
        }
        store.setEnabled(false, id: second.id)
        expect(changed.withLock { $0 }, "screen construction observes library changes")
        expect(screen().rows.isEmpty, "a rebuilt screen drops disabled results")
        _ = screen().body(selection: 0, scroll: ScrollIntent())
        expect(
            EmptyResults.lastText == "No matching commands",
            "a missing match differs from an empty library")
        store.setEnabled(false, id: first.id)
        _ = screen().body(selection: 0, scroll: ScrollIntent())
        expect(
            EmptyResults.lastText == "No custom commands yet",
            "disabled-only libraries have no runnable rows")

        let queryChanged = Mutex(false)
        withObservationTracking {
            _ = screen()
        } onChange: {
            queryChanged.withLock { $0 = true }
        }
        vm.query = ""
        expect(queryChanged.withLock { $0 }, "screen construction observes query changes")
        expect(!full.perform(.edit, at: -1), "negative selections cannot edit")
        expect(!full.perform(.edit, at: full.rows.count), "out-of-range selections cannot edit")
        expect(
            !full.perform(.commandDelete, at: full.rows.count),
            "out-of-range selections cannot delete")
        expect(empty.actions(at: 0)?.items.count == 1, "empty libraries keep the create action")
        print("\(passes) passed, \(failures) failed")
        if failures > 0 { exit(1) }
    }

    static func expect(_ condition: Bool, _ message: String) {
        if condition {
            passes += 1
        } else {
            failures += 1
            print("FAIL: \(message)")
        }
    }
}

@MainActor protocol PaletteScreen {}
struct ScrollIntent {}
enum PaletteShortcut { case newItem, edit, commandDelete }

@MainActor
@Observable
final class PaletteState {
    var query = ""
    var selection = 0
}

@MainActor
final class CustomCommandCoordinator {
    var ran: UUID?
    var deleted: UUID?
    var editRequests: [UUID?] = []
    func editCustomCommand(_ command: CustomCommand?) { editRequests.append(command?.id) }
    func runCustomCommand(id: UUID) { ran = id }
    func deleteCustomCommand(id: UUID) async { deleted = id }
}

struct InterfaceMetrics {
    struct Size { let clipboardListWidth: CGFloat = 200 }
    let size = Size()
}

enum Theme {
    enum Colors { static let separator = Color.gray }
    enum Size { static let hairline: CGFloat = 1 }
}

struct PopoverMenuContent {
    var header: String?
    let items: [PopoverMenuItem]
}

struct PopoverMenuItem {
    let title: String
    let action: () -> Void
    init(
        title: String, systemImage: String, startsSection: Bool = false,
        shortcut: String? = nil, isDestructive: Bool = false, action: @escaping () -> Void
    ) {
        self.title = title
        self.action = action
    }
}

struct EmptyResults: View {
    static var lastText = ""
    init(text: String) { Self.lastText = text }
    var body: some View { EmptyView() }
}

struct CustomCommandList: View {
    let results: [CustomCommand]
    let selectedID: UUID?
    let scroll: ScrollIntent
    let onSelect: (CustomCommand) -> Void
    let onActivate: () -> Void
    let onActions: (CustomCommand) -> Void
    var body: some View { EmptyView() }
}

struct CustomCommandPreview: View {
    let command: CustomCommand?
    var body: some View { EmptyView() }
}
