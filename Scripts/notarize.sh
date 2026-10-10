#!/bin/bash
# Notarize an .app or .dmg, then staple the ticket to it. Usage: notarize.sh <path>
# Credentials come from a `notarytool store-credentials` keychain profile, onecast-notary by default.
set -euo pipefail

TARGET="${1:?usage: notarize.sh <path-to-.app-or-.dmg>}"
PROFILE="${NOTARY_PROFILE:-onecast-notary}"

WORK="$(mktemp -d)"
trap 'rm -rf "$WORK"' EXIT

# notarytool takes a zip, dmg or pkg; an .app goes up as the same ditto zip the updater installs.
SUBMIT="$TARGET"
if [[ "$TARGET" == *.app ]]; then
    SUBMIT="$WORK/submit.zip"
    ditto -c -k --keepParent --sequesterRsrc "$TARGET" "$SUBMIT"
fi

xcrun notarytool submit "$SUBMIT" --keychain-profile "$PROFILE" --wait --output-format json \
    > "$WORK/result.json"
ID="$(plutil -extract id raw "$WORK/result.json")"
STATUS="$(plutil -extract status raw "$WORK/result.json")"
if [ "$STATUS" != "Accepted" ]; then
    echo "✗ Notarization of ${TARGET##*/} ended $STATUS" >&2
    xcrun notarytool log "$ID" --keychain-profile "$PROFILE" >&2 || true
    exit 1
fi
xcrun stapler staple -q "$TARGET"
