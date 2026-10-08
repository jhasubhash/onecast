import SwiftUI

@main
struct OnecastApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var delegate

    // Channel-aware: "Onecast", "Onecast Dev", or "Onecast Beta".
    private let appName = Bundle.main.appDisplayName

    /// Two independent items: one preference each, no state either can read off the other.
    var body: some Scene {
        MenuBarExtra(isInserted: menuBarInsertion) {
            MenuBarMenu(appName: appName)
        } label: {
            MenuBarLabel(appName: appName)
        }
        .commands { menuBarCommands }

        MenuBarExtra(isInserted: calendarMenuBarInsertion) {
            CalendarMenuBarMenu()
        } label: {
            CalendarMenuBarLabel(appName: appName)
        }

        MenuBarExtra(isInserted: presentationMenuBarInsertion) {
            PresentationMenuBarMenu()
        } label: {
            PresentationMenuBarLabel()
        }
    }

    /// Read in `body` for Observation; SwiftUI echoes the binding back, so only a change writes.
    private var menuBarInsertion: Binding<Bool> {
        let settings = AppCore.shared.settings
        let isInserted = settings.showInMenuBar
        return Binding(
            get: { isInserted },
            set: { inserted in
                guard inserted != settings.showInMenuBar else { return }
                settings.showInMenuBar = inserted
            })
    }

    /// Writes through `AppSettings`: dragging the item out must stop the clock and move the picker.
    private var calendarMenuBarInsertion: Binding<Bool> {
        let settings = AppCore.shared.settings
        let isInserted = settings.calendarMenuBarDisplay != .disabled && !isCalendarMenuBarHiddenWhenEmpty
        return Binding(
            get: { isInserted },
            set: { inserted in
                if inserted {
                    guard settings.calendarMenuBarDisplay == .disabled else { return }
                    settings.calendarMenuBarDisplay = .meetingIcon
                } else {
                    // SwiftUI echoes our own removal back here; only a drag-out means "turn it off".
                    guard !isCalendarMenuBarHiddenWhenEmpty, settings.calendarMenuBarDisplay != .disabled
                    else { return }
                    settings.calendarMenuBarDisplay = .disabled
                }
            })
    }

    /// Read in `body`, so Observation re-runs the scene when the coordinator's flag flips.
    private var isCalendarMenuBarHiddenWhenEmpty: Bool {
        AppCore.shared.settings.calendarMenuBarHidesWhenEmpty
            && !AppCore.shared.calendarCoordinator.hasMenuBarEvent
    }

    /// Only while presenting; dragging it out turns the indicator off for next time too.
    private var presentationMenuBarInsertion: Binding<Bool> {
        let settings = AppCore.shared.settings
        let isInserted =
            settings.presentationShowsMenuBarItem && AppCore.shared.presentationCoordinator.isPresenting
        return Binding(
            get: { isInserted },
            set: { inserted in
                // SwiftUI echoes our own removal when a presentation ends; only a drag-out counts.
                let presenting = AppCore.shared.presentationCoordinator.isPresenting
                guard !inserted, presenting, settings.presentationShowsMenuBarItem else { return }
                settings.presentationShowsMenuBarItem = false
            })
    }

    /// Declared, not assigned to `NSApp.mainMenu`: SwiftUI rebuilds the menu on any scene change.
    @CommandsBuilder
    private var menuBarCommands: some Commands {
        CommandGroup(replacing: .appInfo) {
            Button("About \(appName)") { AppCore.shared.settingsCoordinator.showAbout() }
            Button("Check for Updates…") { AppCore.shared.updateCoordinator.checkForUpdates() }
        }
        CommandGroup(replacing: .appSettings) {
            Button("Settings…") { AppCore.shared.settingsCoordinator.showSettings() }
                .keyboardShortcut(",")
        }
        CommandGroup(replacing: .appTermination) {
            Button("Close Settings") { AppCore.shared.settingsCoordinator.closeSettings() }
                .keyboardShortcut("q")
        }
    }
}
