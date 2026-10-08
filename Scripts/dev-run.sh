#!/bin/bash
# Build the Debug app, check its signing identity, quit any running copy and relaunch it.
# The three AGENTS.md rules a verify most often half-runs — relaunch, signing, no stale build — as
# one, then waits until the agent channel answers (custom_docs/AGENT_CONTROL.md).
#
#   ./Scripts/dev-run.sh             build, sign-check, relaunch
#   ./Scripts/dev-run.sh --no-build  relaunch the last build
#   ./Scripts/dev-run.sh --quit      quit Onecast Dev and stop

set -uo pipefail
cd "$(dirname "$0")/.." || exit 1

APP_NAME="Onecast Dev"
APP="$PWD/build/DerivedData/Build/Products/Debug/$APP_NAME.app"
LOG="${TMPDIR:-/tmp}/onecast-dev-build.log"

build=1
case "${1:-}" in
    --no-build) build=0 ;;
    --quit) build=0 ;;
    "") ;;
    *) echo "usage: $0 [--no-build|--quit]" >&2; exit 2 ;;
esac

run_build() {
    echo "› building Debug (log: $LOG)"
    if ! xcodebuild -project Onecast.xcodeproj -scheme Onecast -configuration Debug \
        -derivedDataPath build/DerivedData build > "$LOG" 2>&1; then
        grep -E "error:" "$LOG" | sort -u | head -40 >&2
        echo "✗ build failed — full log: $LOG" >&2
        exit 1
    fi
    local warnings
    warnings=$(grep -E "^/.*warning:" "$LOG" | sort -u)
    if [ -n "$warnings" ]; then
        echo "$warnings" >&2
        echo "! build succeeded with warnings (above)" >&2
    fi
}

# A Developer ID in this keychain but a self-signed build means Signing.local.xcconfig is missing.
check_signing() {
    local identities authority
    identities=$(security find-identity -v -p codesigning | grep "Developer ID Application" \
        | sed -E 's/.*"(Developer ID Application: [^"]+)".*/\1/' | sort -u)
    [ -z "$identities" ] && return 0
    authority=$(codesign -dvv "$APP" 2>&1 | grep -m1 "^Authority=" | cut -d= -f2-)
    case "$authority" in "Developer ID Application"*) return 0 ;; esac
    if [ "$(printf '%s\n' "$identities" | wc -l | tr -d ' ')" -ne 1 ]; then
        echo "✗ several Developer ID identities; create Signing.local.xcconfig by hand:" >&2
        printf '  %s\n' "$identities" >&2
        exit 1
    fi
    local team
    team=$(printf '%s' "$identities" | sed -E 's/.*\(([A-Z0-9]+)\)$/\1/')
    printf 'CODE_SIGN_IDENTITY = %s\nDEVELOPMENT_TEAM = %s\n' "$identities" "$team" \
        > Signing.local.xcconfig
    echo "› signed '$authority'; wrote Signing.local.xcconfig for '$identities', rebuilding clean"
    # An incremental build keeps the helpers' old signatures, which the embed step then refuses.
    xcodebuild -project Onecast.xcodeproj -scheme Onecast -configuration Debug \
        -derivedDataPath build/DerivedData clean > /dev/null 2>&1
    run_build
}

quit_app() {
    pgrep -f "$APP_NAME.app/Contents/MacOS" > /dev/null || return 0
    osascript -e "quit app \"$APP_NAME\"" > /dev/null 2>&1
    for _ in $(seq 1 25); do
        pgrep -f "$APP_NAME.app/Contents/MacOS" > /dev/null || return 0
        sleep 0.2
    done
    pkill -f "$APP_NAME.app/Contents/MacOS"
    sleep 0.5
}

if [ "$build" -eq 1 ]; then
    run_build
    check_signing
fi

echo "› quitting any running $APP_NAME"
quit_app
[ "${1:-}" = "--quit" ] && exit 0

[ -d "$APP" ] || { echo "✗ no build at $APP — run without --no-build" >&2; exit 1; }
echo "› launching $APP_NAME"
open "$APP"
# Ready means the agent channel answers, not merely that a process exists: by then start() ran.
if node Scripts/agent/onecastctl ready 30 > /dev/null; then
    echo "✓ $APP_NAME ready (pid $(pgrep -f "$APP_NAME.app/Contents/MacOS" | head -1))"
    exit 0
fi
echo "✗ $APP_NAME did not answer on the agent channel" >&2
exit 1
