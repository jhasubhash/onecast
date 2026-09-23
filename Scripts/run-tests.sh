#!/bin/bash
# The test suite. There is no XCTest target: each harness compiles the shipped sources it guards,
# so a harness that stops compiling means a decision leaked out of a pure layer. See docs/testing.md.
#
# Never join a compile and its run with `&&`: `set -e` ignores a failure in a non-final AND-OR list
# member, which is how CI reported success over a harness that had not compiled since phase 10.

set -uo pipefail

# Absolute: the workers re-enter this script after the cd, where a relative $0 would not resolve.
SELF="$(cd "$(dirname "$0")" && pwd)/$(basename "$0")"
cd "$(dirname "$0")/.." || exit 1

BIN="${TMPDIR:-/tmp}/onecast-harness"
mkdir -p "$BIN"

# `--exec` is the worker half: xargs re-enters here once per queued harness.
if [ "${1:-}" = "--exec" ]; then
    shift
    name=$1 opt=$2
    shift 2
    : > "$BIN/$name.running"
    trap 'rm -f "$BIN/$name.running" "$BIN/$name.time"' EXIT
    fail() {
        printf '\033[31mFAIL\033[0m  %-25s %s\n' "$name" "$1"
        : > "$BIN/$name.failed"
        exit 0
    }
    TIMEFORMAT=%1R
    if ! compiled=$( { time swiftc -swift-version 6 "$opt" "$@" "Tests/$name.swift" -o "$BIN/$name" > "$BIN/$name.log" 2>&1; } 2>&1 ); then
        fail "did not compile"
    fi
    { time "$BIN/$name" > "$BIN/$name.log" 2>&1; } 2> "$BIN/$name.time" &
    pid=$!
    # macOS ships no `timeout`, so the worker polls; a wedged harness must fail, not stall the suite.
    ticks=0
    while kill -0 "$pid" 2>/dev/null; do
        if [ "$ticks" -ge $((ONECAST_TEST_TIMEOUT * 5)) ]; then
            { pkill -KILL -P "$pid"; kill -KILL "$pid"; wait "$pid"; } 2>/dev/null
            printf '\n[run-tests] killed after %ss without finishing\n' "$ONECAST_TEST_TIMEOUT" >> "$BIN/$name.log"
            fail "timed out after ${ONECAST_TEST_TIMEOUT}s"
        fi
        ticks=$((ticks + 1))
        sleep 0.2
    done
    wait "$pid"
    status=$?
    took=$(< "$BIN/$name.time")
    if [ "$status" -gt 128 ]; then fail "crashed (signal $((status - 128))) after ${took}s"; fi
    if [ "$status" -ne 0 ]; then fail "assertion failed after ${took}s"; fi
    printf '\033[32mok\033[0m    %-25s %5ss  \033[2m(compile %ss)\033[0m\n' "$name" "$took" "$compiled"
    exit 0
fi

QUEUE="$BIN/queue"
: > "$QUEUE"
rm -f "$BIN"/*.failed "$BIN"/*.running

failed=()
ran=0
only="${1:-}"

# `--index` merges each harness's compile command into .compile instead of running anything.
# xcodebuild never compiles the harnesses, so without this nothing in Tests/ resolves in an editor.
# The source lists below are the only copy, which is why this lives here rather than in its own script.
emit_db=0
DB="${TMPDIR:-/tmp}/onecast-compile-db.json"
if [ "$only" = "--index" ]; then
    emit_db=1
    only=""
    printf '[' > "$DB"
fi

# run [slow] [-O] [index] <name> <source...> — queue the harness. `slow` dispatches it in the first
# wave; `index` claims editor flags for a harness that is compiled by hand rather than by the suite.
run() {
    local opt=-Onone pri=1 index_only=0
    while :; do
        case "$1" in
            slow)  pri=0; shift;;
            -O)    opt=-O; shift;;
            index) index_only=1; shift;;
            *)     break;;
        esac
    done
    local name=$1
    shift
    if [ -n "$only" ] && [ "$name" != "$only" ]; then return 0; fi
    if [ "$index_only" -eq 1 ] && [ "$emit_db" -eq 0 ]; then return 0; fi
    ran=$((ran + 1))

    # Absolute paths throughout: sourcekit-lsp resolves the command itself and does not apply
    # `directory` to relative arguments, so a relative path there silently yields no index.
    if [ "$emit_db" -eq 1 ]; then
        local sources=()
        for source in "$@" "Tests/$name.swift"; do sources+=("$PWD/$source"); done
        [ "$ran" -gt 1 ] && printf ',' >> "$DB"
        printf '{"directory":"%s","command":"swiftc -swift-version 6 -sdk %s' \
            "$PWD" "$(xcrun --show-sdk-path --sdk macosx)" >> "$DB"
        printf ' %s' "${sources[@]}" >> "$DB"
        # Claim every file under `Tests/`: the harness and any helper compiled beside it. A shipped
        # source stays unclaimed, because it would get this short command instead of the app's full
        # one and `.compile` is last-wins — but the app never compiles anything in `Tests/`.
        local claimed=""
        for source in "${sources[@]}"; do
            case "$source" in *"/Tests/"*) claimed="$claimed${claimed:+,}\"$source\"";; esac
        done
        printf '","files":[%s]}' "$claimed" >> "$DB"
        return 0
    fi

    # xargs splits the queue on whitespace, so no harness source path may contain a space.
    printf '%s %s %s %s\n' "$pri" "$name" "$opt" "$*" >> "$QUEUE"
}

L=Onecast/Features/Launcher/Model
run slow -O fuzz-test      $L/SearchRelevance.swift $L/ScriptRomanization.swift \
                           $L/EntryNaming.swift $L/LauncherOrder.swift
run slow -O corpus-test    $L/SearchRelevance.swift $L/ScriptRomanization.swift \
                           $L/EntryNaming.swift $L/LauncherOrder.swift \
                           $L/LauncherRankingStore.swift
run file-search-test       $L/SearchRelevance.swift \
                           Onecast/Features/FileSearch/Model/*.swift
run file-search-session-test Onecast/Platform/Signposts.swift \
                             $L/SearchRelevance.swift \
                             Onecast/Features/FileSearch/Model/*.swift \
                             Onecast/Features/FileSearch/Service/*.swift
run menu-search-test       $L/SearchRelevance.swift \
                           Onecast/Features/MenuSearch/Model/*.swift \
                           Onecast/Features/MenuSearch/Service/*.swift
run window-switch-test     $L/SearchRelevance.swift \
                           Onecast/Features/WindowSwitcher/Model/*.swift
run index file-search-performance Onecast/Platform/Signposts.swift \
                           $L/SearchRelevance.swift \
                           Onecast/Features/FileSearch/Model/*.swift \
                           Onecast/Features/FileSearch/Service/FileSearchService.swift
run ranking-test           $L/SearchRelevance.swift $L/LauncherRankingStore.swift
run scopes-test            $L/SearchScopes.swift \
                           Onecast/Features/Launcher/Service/AppBundleScanner.swift
run app-name-test          Onecast/Platform/AppDisplayName.swift \
                           Onecast/Platform/BundleLocalization.swift \
                           $L/SearchRelevance.swift
run favorites-test         $L/FavoriteSlots.swift
run apple-shortcut-test    Onecast/Features/AppleShortcuts/Model/*.swift
run calc-test              Onecast/Features/Calculator/Model/*.swift
run index calc-performance Onecast/Features/Calculator/Model/*.swift
run calendar-test          Onecast/Features/Calendar/Model/*.swift
run clipboard-test         Onecast/Features/Clipboard/Model/ClipboardStore.swift \
                           Onecast/Features/Clipboard/Model/ClipboardFilter.swift \
                           Onecast/Features/Clipboard/Model/ClipboardFileKind.swift \
                           Onecast/Features/Clipboard/Model/ColorValue.swift \
                           Onecast/Features/Clipboard/Model/ColorFormat.swift \
                           Onecast/Features/Clipboard/Model/ColorSpaces.swift
# `Q` is the URL detector a drag payload builds its link with, rather than a second one.
Q=Onecast/Features/Quicklinks/Model/QuicklinkDestination.swift
run clipboard-search-test  Onecast/Features/Clipboard/Model/*.swift $Q
run clipboard-text-test    Onecast/Features/Clipboard/Model/*.swift $Q \
                           Onecast/Features/Clipboard/Service/ClipboardTextExtractor.swift \
                           Onecast/Features/Clipboard/Service/ClipboardTextIndexer.swift \
                           Onecast/Features/Clipboard/Service/ClipboardTextWorker.swift
run pasteboard-test        Onecast/Platform/PasteboardFiles.swift \
                           Onecast/Features/Clipboard/Model/ClipboardStore.swift \
                           Onecast/Features/Clipboard/Model/ClipboardFilter.swift \
                           Onecast/Features/Clipboard/Model/ColorValue.swift \
                           Onecast/Features/Clipboard/Model/ColorFormat.swift \
                           Onecast/Features/Clipboard/Model/ColorSpaces.swift \
                           Onecast/Features/Clipboard/Service/ClipboardManager.swift \
                           Onecast/Features/Clipboard/Service/Paster.swift
run index clipboard-file-performance \
                           Onecast/Platform/PasteboardFiles.swift \
                           Onecast/Features/Clipboard/Model/ClipboardStore.swift \
                           Onecast/Features/Clipboard/Model/ClipboardFilter.swift \
                           Onecast/Features/Clipboard/Model/ColorValue.swift \
                           Onecast/Features/Clipboard/Model/ColorFormat.swift \
                           Onecast/Features/Clipboard/Model/ColorSpaces.swift \
                           Onecast/Features/Clipboard/Service/ClipboardManager.swift
run emoji-test             Onecast/Features/Emoji/Model/EmojiCatalog.swift \
                           Onecast/Features/Emoji/Model/EmojiGridGeometry.swift \
                           Onecast/Features/Emoji/Model/EmojiData.generated.swift
run emoji-search-test      Onecast/Features/Emoji/Model/EmojiCatalog.swift \
                           Onecast/Features/Emoji/Model/EmojiData.generated.swift \
                           Onecast/Features/Emoji/Service/EmojiIndex.swift \
                           Onecast/Features/Emoji/Service/FrequentEmojiStore.swift \
                           Onecast/Features/Emoji/Service/PinnedEmojiStore.swift \
                           Onecast/Features/Launcher/Model/SearchRelevance.swift \
                           Onecast/Platform/AppPaths.swift Onecast/Platform/Memo.swift
run index emoji-search-performance \
                           Onecast/Features/Emoji/Model/EmojiCatalog.swift \
                           Onecast/Features/Emoji/Model/EmojiData.generated.swift \
                           Onecast/Features/Emoji/Service/EmojiIndex.swift \
                           Onecast/Features/Emoji/Service/FrequentEmojiStore.swift \
                           Onecast/Features/Launcher/Model/SearchRelevance.swift \
                           Onecast/Platform/AppPaths.swift Onecast/Platform/Memo.swift
run palette-selection-test Onecast/Features/PaletteRowIndex.swift \
                           Onecast/Features/Emoji/Model/EmojiGridGeometry.swift
run appearance-test        Onecast/Platform/Appearance.swift \
                           Onecast/DesignSystem/Theme.swift \
                           Onecast/DesignSystem/InterfaceMetrics.swift \
                           Onecast/Features/Settings/AppAppearance.swift
run interface-size-test    Onecast/Platform/Appearance.swift \
                           Onecast/DesignSystem/Theme.swift \
                           Onecast/DesignSystem/InterfaceMetrics.swift \
                           Onecast/Features/Settings/InterfaceSize.swift \
                           Onecast/Features/Extensions/Model/ExtensionFormMetrics.swift
run palette-placement-test Onecast/Platform/Appearance.swift \
                           Onecast/DesignSystem/Theme.swift \
                           Onecast/DesignSystem/InterfaceMetrics.swift \
                           Onecast/Features/Settings/InterfaceSize.swift \
                           Onecast/Palette/PalettePlacement.swift
run scroll-reveal-test     Onecast/DesignSystem/Scrolling/SelectionReveal.swift
run redaction-test         Onecast/DesignSystem/RedactedPlaceholder.swift
run keyboard-focus-test    Onecast/DesignSystem/Interaction/KeyboardFocus.swift
run ai-instructions-test   Onecast/Features/AI/Model/AIInstructions.swift \
                           Onecast/Features/AI/Model/AIPreamble.swift \
                           Onecast/Features/AI/Model/Skill.swift
run hover-arming-test      Onecast/Palette/HoverArming.swift \
                           Onecast/Palette/PaletteState.swift \
                           Onecast/Palette/PaletteMode.swift \
                           Onecast/Features/Emoji/Model/EmojiCatalog.swift \
                           Onecast/Features/Clipboard/Model/ClipboardStore.swift \
                           Onecast/Features/Clipboard/Model/ClipboardFilter.swift \
                           Onecast/Features/FileSearch/Model/FileSearchFilter.swift \
                           Onecast/Features/Clipboard/Model/ColorValue.swift \
                           Onecast/Features/Clipboard/Model/ColorFormat.swift \
                           Onecast/Features/Clipboard/Model/ColorSpaces.swift \
                           Onecast/Features/Quicklinks/Model/Quicklink.swift \
                           Onecast/Features/Quicklinks/Model/QuicklinkDestination.swift \
                           Onecast/Features/CustomCommands/Model/CustomCommand.swift
run palette-escape-test    Onecast/Palette/PaletteMode.swift \
                           Onecast/Palette/PaletteEscapeAction.swift \
                           Onecast/Palette/CommandEscapeTap.swift \
                           Onecast/Features/Settings/EscapeKeyBehavior.swift \
                           Onecast/Features/Quicklinks/Model/Quicklink.swift \
                           Onecast/Features/Quicklinks/Model/QuicklinkDestination.swift \
                           Onecast/Features/CustomCommands/Model/CustomCommand.swift
run palette-navigation-test Onecast/Palette/PaletteState.swift \
                           Onecast/Palette/PaletteMode.swift \
                           Onecast/Palette/HoverArming.swift \
                           Onecast/Features/Emoji/Model/EmojiCatalog.swift \
                           Onecast/Features/Clipboard/Model/ClipboardStore.swift \
                           Onecast/Features/Clipboard/Model/ClipboardFilter.swift \
                           Onecast/Features/FileSearch/Model/FileSearchFilter.swift \
                           Onecast/Features/Clipboard/Model/ColorValue.swift \
                           Onecast/Features/Clipboard/Model/ColorFormat.swift \
                           Onecast/Features/Clipboard/Model/ColorSpaces.swift \
                           Onecast/Features/Quicklinks/Model/Quicklink.swift \
                           Onecast/Features/Quicklinks/Model/QuicklinkDestination.swift \
                           Onecast/Features/CustomCommands/Model/CustomCommand.swift
run palette-filter-test    Onecast/Palette/PaletteMode.swift \
                           Onecast/Palette/PaletteFilterAction.swift \
                           Onecast/Features/Quicklinks/Model/Quicklink.swift \
                           Onecast/Features/Quicklinks/Model/QuicklinkDestination.swift \
                           Onecast/Features/CustomCommands/Model/CustomCommand.swift
run palette-shortcut-test  Onecast/Palette/PaletteShortcut.swift
run palette-tab-test       Onecast/Palette/PaletteMode.swift \
                           Onecast/Palette/PaletteTabAction.swift \
                           Onecast/Features/Quicklinks/Model/Quicklink.swift \
                           Onecast/Features/Quicklinks/Model/QuicklinkDestination.swift \
                           Onecast/Features/CustomCommands/Model/CustomCommand.swift
run fallback-test          Onecast/Features/Launcher/Model/Fallback.swift \
                           Onecast/Features/Launcher/Model/CommandID.swift \
                           Onecast/Features/HotKeys/Model/HotKeyAction.swift \
                           Onecast/Features/QuickActions/Model/QuickAction.swift \
                           Onecast/Features/QuickActions/Model/BuiltInQuickAction.swift \
                           Onecast/Features/QuickActions/Model/CustomQuickAction.swift \
                           Onecast/Features/Quicklinks/Model/Quicklink.swift \
                           Onecast/Features/Quicklinks/Model/QuicklinkDestination.swift \
                           Onecast/Features/SystemActions/Model/SystemAction.swift \
                           Onecast/Features/WindowManagement/Model/WindowCommand.swift \
                           Onecast/Features/Intent/Model/*.swift
run intent-test            Onecast/Features/Intent/Model/*.swift
run hotkey-test            Onecast/Features/HotKeys/Model/DoubleTapModifier.swift \
                           Onecast/Features/HotKeys/Model/DoubleTapDetector.swift \
                           Onecast/Features/HotKeys/Model/GlobeTapDetector.swift \
                           Onecast/Features/HotKeys/Model/HotKeyBinding.swift \
                           Onecast/Features/HotKeys/Model/HyperKey.swift \
                           Onecast/Platform/ASCIIKeyboardLayout.swift \
                           Onecast/Features/HotKeys/Service/KeyShortcut.swift \
                           Onecast/Features/HotKeys/Model/HotKeyAction.swift \
                           Onecast/Features/QuickActions/Model/QuickAction.swift \
                           Onecast/Features/QuickActions/Model/BuiltInQuickAction.swift \
                           Onecast/Features/QuickActions/Model/CustomQuickAction.swift \
                           Onecast/Features/Launcher/Model/CommandID.swift \
                           Onecast/Features/Quicklinks/Model/Quicklink.swift \
                           Onecast/Features/Quicklinks/Model/QuicklinkDestination.swift \
                           Onecast/Features/SystemActions/Model/SystemAction.swift \
                           Onecast/Features/WindowManagement/Model/WindowCommand.swift
run callout-test           Onecast/Platform/Appearance.swift \
                           Onecast/DesignSystem/Theme.swift \
                           Onecast/DesignSystem/InterfaceMetrics.swift \
                           Onecast/Features/HotKeys/UI/CalloutPlacement.swift
run icon-cache-test        Onecast/Platform/Appearance.swift \
                           Onecast/Platform/Images/IconCache.swift
run entry-icon-test        Onecast/Platform/Appearance.swift \
                           Onecast/Platform/Images/IconCache.swift \
                           Onecast/Platform/Images/FileIconStamp.swift
run ext-icon-test          Onecast/Platform/Appearance.swift \
                           Onecast/Platform/Images/IconCache.swift \
                           Onecast/Platform/Images/FileIconStamp.swift \
                           Onecast/Platform/Compression/Zlib.swift \
                           Onecast/DesignSystem/Theme.swift \
                           Onecast/DesignSystem/InterfaceMetrics.swift \
                           Onecast/Features/Extensions/Model/ExtensionBootConfig.swift \
                           Onecast/Features/Extensions/Model/ExtensionLaunchType.swift \
                           Onecast/Features/Extensions/Model/ExtensionManifest.swift \
                           Onecast/Platform/AppDisplayName.swift \
                           Onecast/Features/Extensions/Model/ExtensionRefreshPolicy.swift \
                           Onecast/Features/Extensions/Model/ExtensionRefreshState.swift \
                           Onecast/Features/Extensions/Model/RenderNode.swift \
                           Onecast/Features/Extensions/Service/ExtensionCatalog.swift \
                           Onecast/Features/Extensions/Service/ExtensionFetcher.swift \
                           Onecast/Features/Extensions/Service/ExtensionNodeShims.swift \
                           Onecast/Features/Extensions/Service/ExtensionOAuthKeychain.swift \
                           Onecast/Features/Extensions/Service/ExtensionOAuthSession.swift \
                           Onecast/Features/Extensions/Service/ExtensionRuntime.swift \
                           Onecast/Features/Extensions/Service/ExtensionIconCache.swift \
                           Onecast/Features/Extensions/UI/ExtensionAnimatedImage.swift \
                           Onecast/Features/Extensions/UI/ExtensionImage.swift \
                           Onecast/Features/Clipboard/Model/ColorValue.swift \
                           Onecast/Features/Clipboard/Model/ColorSpaces.swift
run system-action-test     Onecast/Features/SystemActions/Model/SystemAction.swift
run volume-test            Onecast/Features/SystemActions/Model/VolumeLevel.swift
run window-command-test    Onecast/Features/WindowManagement/Model/WindowCommand.swift \
                           Onecast/Features/WindowManagement/Model/WindowCycle.swift \
                           Onecast/Features/WindowManagement/Model/WindowPlacementEngine.swift \
                           Onecast/Features/WindowManagement/Model/WindowActionMemory.swift
run space-gesture-test     Onecast/Features/WindowManagement/Model/WindowCommand.swift \
                           Onecast/Features/WindowManagement/Model/SpaceGesture.swift
run window-layout-test     Onecast/Features/WindowManagement/Model/WindowCommand.swift \
                           Onecast/Features/WindowManagement/Model/WindowCycle.swift \
                           Onecast/Features/WindowManagement/Model/WindowPlacementEngine.swift \
                           Onecast/Features/WindowManagement/Model/WindowLayoutAnchor.swift \
                           Onecast/Features/WindowManagement/Model/WindowLayoutDisplay.swift \
                           Onecast/Features/WindowManagement/Model/WindowLayout.swift \
                           Onecast/Features/WindowManagement/Model/WindowLayoutGeometry.swift \
                           Onecast/Features/WindowManagement/Model/WindowLayoutPlan.swift \
                           Onecast/Features/WindowManagement/Model/WindowLayoutStore.swift \
                           Onecast/Features/WindowManagement/Model/CustomWindowSize.swift \
                           Onecast/Features/WindowManagement/Model/CustomWindowSizeStore.swift
run custom-command-test    Onecast/Platform/PseudoTerminal.swift \
                           Onecast/Features/CustomCommands/Model/CustomCommand.swift \
                           Onecast/Features/CustomCommands/Model/RaycastScriptImport.swift \
                           Onecast/Features/CustomCommands/Service/ShellCommandRunner.swift \
                           Onecast/Features/CustomCommands/Service/CustomCommandArgumentSession.swift
run uninstall-test         Onecast/Features/Uninstall/Model/UninstallTarget.swift \
                           Onecast/Features/Uninstall/Model/UninstallSearchRoot.swift \
                           Onecast/Features/Uninstall/Model/UninstallRules.swift \
                           Onecast/Features/Uninstall/Model/UninstallProtection.swift \
                           Onecast/Features/Uninstall/Model/UninstallPlan.swift
run quicklink-test         Onecast/Features/Quicklinks/Model/Quicklink.swift \
                           Onecast/Features/Quicklinks/Model/QuicklinkDestination.swift \
                           Onecast/Features/Quicklinks/Model/QuicklinkStore.swift \
                           Onecast/Features/Quicklinks/Model/QuicklinkArchive.swift \
                           Onecast/Features/Quicklinks/Model/RaycastQuicklinkImport.swift \
                           Onecast/Features/Quicklinks/UI/QuicklinkDraft.swift
run slow snippets-test     Onecast/Platform/NotificationToken.swift \
                           Onecast/Platform/HealthTicker.swift \
                           Onecast/Platform/AccessibilityText.swift \
                           Onecast/Features/Snippets/Model/*.swift \
                           Onecast/Features/Snippets/Service/*.swift \
                           Onecast/Features/TextInjection/Service/*.swift
run notes-test             Onecast/Platform/Signposts.swift \
                           $L/SearchRelevance.swift \
                           Onecast/Features/Notes/Model/*.swift \
                           Onecast/Features/Notes/Service/*.swift
run notes-editor-test      Onecast/Platform/Signposts.swift \
                           Onecast/Platform/Appearance.swift \
                           Onecast/DesignSystem/Theme.swift \
                           Onecast/DesignSystem/InterfaceMetrics.swift \
                           Onecast/Features/TextInjection/Service/InjectableTextView.swift \
                           Onecast/Features/Notes/Model/NoteDocument.swift \
                           Onecast/Features/Notes/UI/NoteTextView.swift \
                           Onecast/Features/Notes/UI/NoteEditorView.swift
run slow -O raycast-test   Onecast/Features/Backup/Model/RaycastImportError.swift \
                           Onecast/Features/Backup/Service/RaycastDecoder.swift \
                           Onecast/Features/Backup/Service/Scrypt.swift \
                           Onecast/Platform/Compression/Zlib.swift
run settings-backup-test   Onecast/Features/Settings/AppSettingsKey.swift \
                           Onecast/Features/Backup/Model/SettingsBackupCoverage.swift
run backup-archive-test    Onecast/Platform/AppPaths.swift \
                           Onecast/Features/Backup/Model/BackupArchive.swift \
                           Onecast/Features/Backup/Model/BackupBundle.swift \
                           Onecast/Features/Backup/Model/BackupCategory.swift \
                           Onecast/Features/Backup/Model/BackupClipboardItem.swift \
                           Onecast/Features/Backup/Model/BackupManifest.swift \
                           Onecast/Features/Backup/Service/BackupStaging.swift
E=Onecast/Features/Extensions
run symbols-test           $E/Service/SymbolCatalog.swift
run ext-cleanup-test       $E/Service/ExtensionCleanup.swift \
                           $E/Service/ExtensionCatalog.swift \
                           $E/Model/ExtensionManifest.swift \
                           Onecast/Platform/AppDisplayName.swift \
                           $E/Model/ExtensionLaunchType.swift \
                           $E/Model/ExtensionRefreshPolicy.swift \
                           $E/Model/ExtensionRefreshState.swift
run ext-refresh-test       $E/Model/ExtensionManifest.swift \
                           Onecast/Platform/AppDisplayName.swift \
                           $E/Model/ExtensionLaunchType.swift \
                           $E/Model/ExtensionRefreshPolicy.swift \
                           $E/Model/ExtensionRefreshState.swift
run ext-metadata-test      $E/Model/ExtensionCommandMetadata.swift \
                           $E/Service/ExtensionCommandMetadataStore.swift
run ext-store-test         $E/Model/ExtensionRegistry.swift \
                           $E/Model/ExtensionPackageManager.swift \
                           $E/Model/ExtensionStoreResponse.swift
run ext-form-test          $E/Model/ExtensionFormMetrics.swift \
                           $E/Model/ExtensionFormField.swift \
                           $E/UI/ExtensionFormKey.swift \
                           $E/Model/ExtensionDateExpression.swift \
                           $E/UI/ExtensionListKey.swift \
                           Tests/ext-list-key-test.swift
run ext-image-size-test    $E/Model/ExtensionImageSize.swift
run ext-accessory-test     $E/Model/RenderNode.swift \
                           $E/Model/ExtensionPickerItem.swift \
                           $E/Model/ExtensionSearchAccessory.swift \
                           $E/Service/ExtensionStorage.swift
run slow ext-test          -parse-as-library \
                           Onecast/Platform/Appearance.swift \
                           Onecast/Platform/Images/IconCache.swift \
                           Onecast/Platform/Images/FileIconStamp.swift \
                           Onecast/DesignSystem/Theme.swift \
                           Onecast/DesignSystem/InterfaceMetrics.swift \
                           $E/Model/ExtensionBootConfig.swift \
                           $E/Model/ExtensionDeepLink.swift \
                           $E/Model/ExtensionLaunchType.swift \
                           $E/Model/ExtensionFormField.swift \
                           $E/Model/ExtensionGridLayout.swift \
                           $E/Model/ExtensionManifest.swift \
                           Onecast/Platform/AppDisplayName.swift \
                           $E/Model/ExtensionRefreshPolicy.swift \
                           $E/Model/ExtensionRefreshState.swift \
                           $E/Model/RenderNode.swift \
                           $E/Model/ExtensionPickerItem.swift \
                           $E/Model/ExtensionSearchAccessory.swift \
                           $E/Service/ExtensionCatalog.swift \
                           $E/Service/ExtensionFetcher.swift \
                           $E/Service/ExtensionIconCache.swift \
                           $E/Service/ExtensionNodeShims.swift \
                           $E/Service/ExtensionOAuthKeychain.swift \
                           $E/Service/ExtensionOAuthSession.swift \
                           $E/Service/ExtensionRuntime.swift \
                           $E/UI/ExtensionAnimatedImage.swift \
                           $E/UI/ExtensionImage.swift \
                           $E/UI/ExtensionScreen.swift \
                           $L/SearchRelevance.swift \
                           Onecast/Platform/Compression/Zlib.swift \
                           Onecast/Features/Clipboard/Model/ColorValue.swift \
                           Onecast/Features/Clipboard/Model/ColorSpaces.swift
run settings-history-test  Onecast/Features/Settings/SettingsTab.swift \
                           Onecast/Features/Settings/SettingsHistory.swift \
                           Onecast/Features/Settings/SettingsAnchor.swift \
                           Onecast/Features/Settings/SettingsNavigationState.swift \
                           Onecast/Features/Settings/SettingsSearchCatalog.swift \
                           $L/SearchRelevance.swift
run updates-test           Onecast/Features/Updates/Model/*.swift \
                           Onecast/Features/Updates/Service/BundleSignature.swift
run support-test           Onecast/Features/Support/Model/*.swift
run scheduler-test         Onecast/Features/Notifications/Model/NotificationSpec.swift \
                           Onecast/Features/Scheduler/Model/*.swift
run scheduler-ai-test      Onecast/Features/Notifications/Model/NotificationSpec.swift \
                           Onecast/Features/Scheduler/Model/*.swift \
                           Onecast/Features/Scheduler/Service/ScheduledTaskStore.swift \
                           Onecast/Features/AI/Model/AIRequest.swift \
                           Onecast/Features/AI/Model/AITool.swift \
                           Onecast/Features/AI/Model/JSONValue.swift \
                           Onecast/Features/Scheduler/AI/SchedulerAITool.swift
run ai-provider-test       Onecast/Features/Settings/AppSettingsKey.swift \
                           Onecast/Features/AI/Model/*.swift \
                           Onecast/Features/AI/Settings/AISettingsStore.swift
run assistant-test         Onecast/Features/AI/Model/*.swift \
                           Onecast/Features/AI/Service/AssistantSecretStore.swift \
                           Onecast/Platform/KeychainSecretStore.swift
run ai-chat-test           Onecast/Features/AI/Model/AIRequest.swift \
                           Onecast/Features/AI/Model/AIAttachmentPolicy.swift \
                           Onecast/Features/AI/Model/AIRetention.swift \
                           Onecast/Features/AI/Model/AITool.swift \
                           Onecast/Features/AI/Model/JSONValue.swift \
                           Onecast/Features/AI/Model/ChatMessage.swift \
                           Onecast/Features/AI/Model/ChatSession.swift \
                           Onecast/Features/AI/Model/MarkdownBlock.swift \
                           Onecast/Features/AI/Service/AIProvider.swift \
                           Onecast/Features/AI/Service/ChatHistoryStore.swift \
                           Onecast/Features/AI/Service/AIToolLoopProvider.swift \
                           Onecast/Features/AI/UI/AIChatState.swift
run mcp-test               Onecast/Features/Settings/AppSettingsKey.swift \
                           Onecast/Features/AI/Model/AIConnection.swift \
                           Onecast/Features/AI/Model/AppleIntelligence.swift \
                           Onecast/Features/AI/Model/AIRequest.swift \
                           Onecast/Features/AI/Model/AITool.swift \
                           Onecast/Features/AI/Model/JSONValue.swift \
                           Onecast/Features/MCP/Model/*.swift \
                           Onecast/Features/MCP/Settings/MCPSettingsStore.swift
run -O text-diff-test      Onecast/Features/QuickActions/Model/TextDiffEngine.swift
run index text-diff-performance Onecast/Features/QuickActions/Model/TextDiffEngine.swift
run quick-action-test      Onecast/Features/Settings/AppSettingsKey.swift \
                           Onecast/Features/AI/Model/AIConnection.swift \
                           Onecast/Features/AI/Model/AppleIntelligence.swift \
                           Onecast/Features/AI/Model/ChatGPTSubscription.swift \
                           Onecast/Features/AI/Model/InstalledAI.swift \
                           Onecast/Features/QuickActions/Model/*.swift \
                           Onecast/Features/QuickActions/Settings/QuickActionSettingsStore.swift
run apple-intelligence-test Onecast/Features/Settings/AppSettingsKey.swift \
                           Onecast/Features/AI/Model/*.swift \
                           Onecast/Features/AI/Service/AIProvider.swift \
                           Onecast/Features/AI/Service/AppleIntelligenceProvider.swift \
                           Onecast/Features/AI/Service/AppleIntelligenceHostTool.swift
run slow mcp-stdio-test    Onecast/Platform/ExecutableLocator.swift \
                           Onecast/Platform/KeychainSecretStore.swift \
                           Onecast/Features/Settings/AppSettingsKey.swift \
                           Onecast/Features/AI/Model/AIConnection.swift \
                           Onecast/Features/AI/Model/AppleIntelligence.swift \
                           Onecast/Features/AI/Model/AITool.swift \
                           Onecast/Features/AI/Model/AIStreamDecoder.swift \
                           Onecast/Features/AI/Model/AIRequest.swift \
                           Onecast/Features/AI/Model/JSONValue.swift \
                           Onecast/Features/MCP/Model/*.swift \
                           Onecast/Features/MCP/Service/*.swift
run slow codex-turn-test   Onecast/Platform/AppPaths.swift \
                           Onecast/Features/AI/Model/*.swift \
                           Onecast/Features/AI/Service/AIProvider.swift \
                           Onecast/Features/AI/Service/ChatGPTSubscriptionManager.swift \
                           Onecast/Features/AI/Service/CodexAppServerClient.swift \
                           Onecast/Platform/ExecutableLocator.swift \
                           Onecast/Features/AI/Service/CodexTurnRunner.swift
run installed-ai-test     Onecast/Features/AI/Model/*.swift \
                          Onecast/Features/AI/Service/AIProvider.swift \
                          Onecast/Platform/AppPaths.swift \
                          Onecast/Platform/ExecutableLocator.swift \
                          Onecast/Features/AI/Service/InstalledCLIProvider.swift \
                          Onecast/Features/AI/Service/InstalledAIManager.swift
run computer-use-token-test Onecast/Features/AI/Model/ComputerUseTokenLedger.swift
run slow computer-use-bridge-test \
                           Onecast/Features/AI/Service/ComputerUseBridge.swift \
                           Onecast/Features/AI/Service/ComputerController.swift \
                           Onecast/Features/AI/Service/ComputerUseTool.swift \
                           Onecast/Features/AI/Model/ComputerUseTokenLedger.swift \
                           Onecast/Features/AI/Model/AICLIToolConfig.swift \
                           Onecast/Features/AI/Model/AITool.swift \
                           Onecast/Features/AI/Model/AIRequest.swift \
                           Onecast/Features/AI/Model/JSONValue.swift \
                           Onecast/Platform/Permissions.swift \
                           Onecast/Platform/CameraAccess.swift \
                           Onecast/Platform/CalendarAccess.swift
run assistant-store-test   Onecast/Features/Settings/AppSettingsKey.swift \
                           Onecast/Features/AI/Model/*.swift \
                           Onecast/Features/AI/Service/AssistantStore.swift \
                           Onecast/Features/AI/Service/SkillStore.swift
run plugin-catalog-test    Onecast/Platform/AppPaths.swift \
                           Onecast/Features/Plugins/Service/PluginCatalog.swift

if [ "$emit_db" -eq 1 ]; then
    printf ']\n' >> "$DB"
    [ -f .compile ] || echo '[]' > .compile
    node -e '
const fs = require("node:fs");
const [comp, db] = process.argv.slice(1);
const existing = JSON.parse(fs.readFileSync(comp, "utf8"));
const harnesses = JSON.parse(fs.readFileSync(db, "utf8"));
const kept = existing.filter((e) => !(e.files || []).some((f) => f.includes("/Tests/")));
fs.writeFileSync(comp, JSON.stringify([...kept, ...harnesses], null, 1));
console.log(harnesses.length + " harness entries indexed into .compile");
' .compile "$DB"
    exit 0
fi

if [ "$ran" -eq 0 ]; then
    echo "No harness named '$only'." >&2
    exit 2
fi

# `sort -s` is stable, so the slow harnesses lead and everything else keeps its declaration order.
JOBS="${ONECAST_TEST_JOBS:-$(sysctl -n hw.ncpu)}"
export ONECAST_TEST_TIMEOUT="${ONECAST_TEST_TIMEOUT:-300}"
started=$SECONDS

# Numbers each result, and names what is still running whenever the output goes quiet.
report() {
    local finished=0 line asked running file
    while :; do
        asked=$SECONDS
        if IFS= read -r -t 15 line; then
            case "$line" in "dispatch "*) return "${line#dispatch }";; esac
            finished=$((finished + 1))
            printf '[%*d/%d] %s\n' "${#ran}" "$finished" "$ran" "$line"
            continue
        fi
        # Bash 3.2 returns the same status for a timeout and EOF; only EOF comes back at once.
        if [ $((SECONDS - asked)) -lt 10 ]; then return 1; fi
        running=""
        for file in "$BIN"/*.running; do
            [ -e "$file" ] && running="$running $(basename "$file" .running)"
        done
        printf '        \033[2mstill running after %ds:%s\033[0m\n' $((SECONDS - started)) "$running"
    done
}

# Without this the suite reports "all passed" whenever dispatch itself dies and no harness ran.
if ! { sort -s -k1,1n "$QUEUE" | cut -d' ' -f2- | xargs -P "$JOBS" -L1 "$SELF" --exec; echo "dispatch $?"; } | report; then
    echo "harness dispatch failed; no result below can be trusted" >&2
    exit 1
fi
elapsed=$((SECONDS - started))

# A compiler diagnostic is far longer than PIPE_BUF, so the workers log it and it is replayed here.
while read -r _ name _; do
    if [ -f "$BIN/$name.failed" ]; then failed+=("$name"); fi
done < "$QUEUE"

if [ ${#failed[@]} -gt 0 ]; then
    for name in "${failed[@]}"; do
        printf '\n\033[31m--- %s ---\033[0m\n' "$name"
        cat "$BIN/$name.log"
    done
    printf '\n\033[31mFAILED\033[0m  %d of %d harness(es) failed in %ds: %s\n' \
        "${#failed[@]}" "$ran" "$elapsed" "${failed[*]}" >&2
    exit 1
fi
printf '\n\033[32mPASSED\033[0m  All %d harness(es) passed in %ds.\n' "$ran" "$elapsed"
