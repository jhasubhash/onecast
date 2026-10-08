#!/bin/bash
# Fails if a Release build carries any of the agent channel. Pass a built Onecast.app to check
# that one; with no argument it builds an unsigned Release into build/ReleaseCheck first.
set -uo pipefail
cd "$(dirname "$0")/../.." || exit 1

app="${1:-}"
if [ -z "$app" ]; then
    echo "› building unsigned Release into build/ReleaseCheck"
    if ! xcodebuild -project Onecast.xcodeproj -scheme Onecast -configuration Release \
        -derivedDataPath build/ReleaseCheck CODE_SIGNING_ALLOWED=NO build > /dev/null 2>&1; then
        echo "✗ Release build failed" >&2
        exit 1
    fi
    app=$(find build/ReleaseCheck/Build/Products/Release -maxdepth 1 -name "*.app" | head -1)
fi
# Every Mach-O in the bundle's MacOS folder: a Debug build keeps its code in a `.debug.dylib`.
leaks=$(for binary in "$app"/Contents/MacOS/*; do
    { nm -m "$binary" 2>/dev/null; strings "$binary"; }
done | grep -E "AgentControlServer|AgentKeyboard|AgentAccessibilityReader|AgentWindowCapture|agent-control\.json" \
    | sort -u)
if [ -n "$leaks" ]; then
    echo "$leaks" | head -10 >&2
    echo "✗ the agent channel is in this build: $app" >&2
    exit 1
fi
echo "✓ no agent channel in $app"
