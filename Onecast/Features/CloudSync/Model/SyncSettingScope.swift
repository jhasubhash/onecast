import Foundation

/// Which category carries each setting; nil keeps it on this Mac. Exhaustive by construction.
enum SyncSettingScope {
    /// Open at Login has no settings.json key: `LaunchAtLogin` owns it, not `UserDefaults`.
    static let launchAtLoginKey = "general.launchAtLogin"

    static func category(of key: String) -> SyncCategory? {
        if key == launchAtLoginKey { return .launchAtLogin }
        return SettingsFileKey(rawValue: key).flatMap(category)
    }

    static var syncedKeys: [String] {
        [launchAtLoginKey] + SettingsFileKey.allCases.filter { category(of: $0) != nil }.map(\.rawValue)
    }

    static func category(of key: SettingsFileKey) -> SyncCategory? {
        switch key {
        // A feature's switch is enabled per Mac, and a folder, scope or device names this Mac.
        case .applicationsEnabled, .searchScopes, .systemSettingsEnabled,
            .systemActionsEnabled, .builtInCommandsEnabled, .customCommandsEnabled,
            .quicklinksEnabled, .appleShortcutsEnabled, .aiEnabled, .dictationModel,
            .dictationMicrophone, .fileSearchEnabled, .fileSearchScopes, .notesEnabled,
            .notesFolder, .snippetsFolder, .navigationEnabled, .windowManagementEnabled,
            .clipboardEnabled, .shelfEnabled, .presentationEnabled, .teleprompterEnabled,
            .presentationDisplays, .presentationSpaces:
            nil
        case .showInMenuBar: .showInMenuBar
        case .appearance, .animationsEnabled: .appearance
        case .interfaceSize: .interfaceSize
        case .compactMode, .compactBarCommands: .windowMode
        case .aiSystemPrompt, .aiSystemPromptEnabled: .aiCommands
        case .dictationMode, .dictationPlaysSounds, .dictationDestination,
            .dictationAdaptsCapitalization, .dictationIdleRelease, .dictationTypesWhileSpeaking,
            .dictationLanguage:
            .dictation
        case .customWindowSizes, .windowLayouts: .windowLayouts
        case .launcherShortcut, .hyperKey, .hyperKeyIncludesShift, .hyperKeyQuickPress,
            .hyperKeySecureInputCompatibility, .applications, .systemSettings, .systemActions,
            .builtInCommands, .customCommandCommands, .quicklinkCommands, .aiCommands,
            .aiBarShortcut, .quickActionCommands, .dictationShortcut, .fileSearchCommands,
            .notesCommands, .snippetsCommands, .shelfCommands, .navigationCommands,
            .windowShortcuts, .windowAliases, .windowManagementCommands,
            .presentationStartShortcut, .presentationEndShortcut, .presentationCommands,
            .teleprompterCommands, .docksCommands, .clipboardCommands, .emojiCommands,
            .calendarCommands, .schedulerCommands:
            .hotkeysAndAliases
        case .automaticallyCheckForUpdates, .popToRootTimeout, .escapeKeyBehavior,
            .autoSwitchInputSource, .supportReminders, .openOnCursorScreen, .paletteDraggable,
            .calcNumberStyle, .launcherShowsSuggestions, .rootSearchSensitivity,
            .customCommandsShowInLauncher, .quicklinksShowInLauncher, .quicklinkOpensNewWindow,
            .quicklinkPassesSelectedText, .quicklinkConfirmsBeforeDelete, .aiWebSearch, .aiChoices,
            .aiOpensTo, .aiNewChatAfter, .aiToolRounds, .quickActionLanguage,
            .fileSearchIgnorePatterns, .fileSearchRemovedDefaultPatterns,
            .fileSearchShowInLauncher, .notesShowsInMenuBar, .snippetsShowInLauncher,
            .menuSearchShowsAppleMenu, .menuSearchDisabledApps, .windowManagementShowInLauncher,
            .windowGap, .windowCycle, .windowLayoutsShowInLauncher, .clipboardRetention,
            .clipboardDefaultAction, .clipboardDisabledApps, .emojiSkinTone, .emojiGridColumns,
            .calendarShowInLauncher, .calendarLauncherLimit, .calendarSpan, .joinWindowMinutes,
            .autoJoinConfirms, .autoJoinNamedProvidersOnly, .meetingBrowser,
            .calendarMenuBarDisplay, .menuBarEvents, .menuBarLinkedEventsOnly,
            .calendarMenuBarHidesWhenEmpty, .hideCurrentEvent, .extensionsShowInLauncher,
            .aiRetention, .aiAssistantsShowInLauncher, .aiBarStaysOpen, .aiShowReasoning,
            .quickActionTranslateWithAI, .quickActionAutoLanguageSwap, .quickActionPrimaryLanguage,
            .quickActionSecondaryLanguage, .shelfShakeToOpen, .presentationShowInLauncher,
            .presentationWindowSize, .presentationMarginPercent, .presentationOtherApps,
            .presentationAppSwitch, .presentationRestoresWindows, .presentationHidesDocks,
            .presentationShowsMenuBarItem, .presentationKeepsDisplayAwake,
            .presentationIgnoredApps, .teleprompterMode, .teleprompterSpeed,
            .teleprompterPlacement, .teleprompterTextSize, .teleprompterHighlight,
            .pluginsShowInLauncher, .schedulerShowInLauncher, .schedulerPlaysSound,
            .schedulerDefaultReminderApp:
            .otherSettings
        }
    }
}
