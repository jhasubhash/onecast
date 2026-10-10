#!/bin/bash
# Build, notarize and publish a stable release from this Mac. Usage: ./Scripts/release.sh <version>
# Needs the Developer ID identity in the keychain and a `notarytool store-credentials` profile.
set -euo pipefail

cd "$(dirname "$0")/.." || exit 1
export DEVELOPER_DIR="${DEVELOPER_DIR:-/Applications/Xcode.app/Contents/Developer}"

VERSION="${1:?usage: release.sh <version>, e.g. 0.1.0}"
TAG="v${VERSION}"
REPO="jhasubhash/onecast"
TAP="jhasubhash/homebrew-onecast"
TEAM="KX3L7SJ2KL"
IDENTITY="Developer ID Application"
export NOTARY_PROFILE="${NOTARY_PROFILE:-onecast-notary}"
OUT="build/release/${VERSION}"

fail() {
    echo "✗ $1" >&2
    exit 1
}

[[ "$VERSION" =~ ^[0-9]+\.[0-9]+\.[0-9]+$ ]] || fail "version must be MAJOR.MINOR.PATCH, got $VERSION"
[ -z "$(git status --porcelain)" ] || fail "the working tree has uncommitted changes"
git fetch -q origin
SHA="$(git rev-parse HEAD)"
# The notes and the tag are made on GitHub, so the commit must already be there.
git merge-base --is-ancestor "$SHA" origin/main || fail "HEAD is not on origin/main; push it first"
gh release view "$TAG" --repo "$REPO" >/dev/null 2>&1 && fail "$TAG is already released"
security find-identity -v -p codesigning | grep -q "$IDENTITY: .*($TEAM)" ||
    fail "no '$IDENTITY' identity for team $TEAM in the keychain"
xcrun notarytool history --keychain-profile "$NOTARY_PROFILE" >/dev/null ||
    fail "notary profile '$NOTARY_PROFILE' is missing; run xcrun notarytool store-credentials"

rm -rf "$OUT"
mkdir -p "$OUT"

# One flavor per call: the thin arm64 build Apple silicon downloads, and the universal one for Intel.
build() {
    local archs="$1" prefix="$2"
    local derived="$OUT/DerivedData-${prefix}"
    local app="$derived/Build/Products/Release/Onecast.app"
    echo "▸ Building ${prefix} (${archs})"
    xcodebuild -project Onecast.xcodeproj -scheme Onecast -configuration Release \
        -derivedDataPath "$derived" -quiet \
        ARCHS="$archs" ONLY_ACTIVE_ARCH=NO \
        CODE_SIGN_STYLE=Manual CODE_SIGN_IDENTITY="$IDENTITY" DEVELOPMENT_TEAM="$TEAM" \
        OTHER_CODE_SIGN_FLAGS="--timestamp" \
        MARKETING_VERSION="$VERSION" CURRENT_PROJECT_VERSION="$(git rev-list --count HEAD)" \
        build

    # A bundled helper is shipped code too: every binary carries exactly the slices asked for.
    for bin in "$app/Contents/MacOS/Onecast" "$app/Contents/Helpers/ClipboardTextHelper" \
        "$app/Contents/Helpers/AIToolHelper" \
        "$app/Contents/Helpers/Onecast Dictation.app/Contents/MacOS/Onecast Dictation"; do
        local slices
        slices="$(lipo -archs "$bin" | tr ' ' '\n' | sort | xargs)"
        [ "$slices" = "$(echo "$archs" | tr ' ' '\n' | sort | xargs)" ] ||
            fail "${bin##*/}: expected '$archs', got '$slices'"
    done
    ./Scripts/verify-signature.sh "$app"

    echo "▸ Notarizing ${prefix}.app"
    ./Scripts/notarize.sh "$app"

    local stage
    stage="$(mktemp -d)"
    cp -R "$app" "$stage/"
    ln -s /Applications "$stage/Applications"
    diskutil image create from "$stage" --format UDZO --volumeName "Onecast" \
        "$OUT/${prefix}-${VERSION}.dmg" >/dev/null
    rm -rf "$stage"
    # The only zip that leaves the signature verifiable, which the in-app updater requires.
    ditto -c -k --keepParent --sequesterRsrc "$app" "$OUT/${prefix}-${VERSION}.zip"

    echo "▸ Notarizing ${prefix}-${VERSION}.dmg"
    ./Scripts/notarize.sh "$OUT/${prefix}-${VERSION}.dmg"
}

build arm64 Onecast
build "arm64 x86_64" Onecast-Universal

echo "▸ Publishing ${TAG}"
CHANNEL=stable TAG="$TAG" SHA="$SHA" VERSION="$VERSION" \
    ./Scripts/release-notes.sh "$OUT/notes.md" "$OUT/discord.md"
# The thin zip goes first: clients predating architecture-aware selection take the first zip.
gh release create "$TAG" --repo "$REPO" --target "$SHA" --title "Onecast ${VERSION}" \
    --notes-file "$OUT/notes.md" \
    "$OUT/Onecast-${VERSION}.dmg" "$OUT/Onecast-${VERSION}.zip" \
    "$OUT/Onecast-Universal-${VERSION}.dmg" "$OUT/Onecast-Universal-${VERSION}.zip"

echo "▸ Updating the ${TAP} casks"
TAP_DIR="$(mktemp -d)"
trap 'rm -rf "$TAP_DIR"' EXIT
gh repo clone "$TAP" "$TAP_DIR" -- --depth 1 -q
for pair in "onecast:Onecast" "onecast-universal:Onecast-Universal"; do
    cask="${pair%%:*}" prefix="${pair#*:}"
    sum="$(shasum -a 256 "$OUT/${prefix}-${VERSION}.dmg" | awk '{print $1}')"
    # Anchored to the casks' two-space indent, so nothing but these two lines can change.
    sed -i '' -E "s|^  version \".*\"|  version \"${VERSION}\"|" "$TAP_DIR/Casks/${cask}.rb"
    sed -i '' -E "s|^  sha256 \".*\"|  sha256 \"${sum}\"|" "$TAP_DIR/Casks/${cask}.rb"
done
git -C "$TAP_DIR" commit -qam "Onecast ${VERSION}"
git -C "$TAP_DIR" push -q

echo "✓ Released ${TAG}: https://github.com/${REPO}/releases/tag/${TAG}"
