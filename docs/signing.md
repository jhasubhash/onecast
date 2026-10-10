# Signing

Onecast is signed with a **stable self-signed identity** called `Onecast Self-Signed`. Keeping the
_same_ identity on every build is what makes macOS remember the Accessibility permission across
rebuilds and updates — ad-hoc signing changes every build and macOS forgets the grant.

Releases sign with a Developer ID and are notarized; see [below](#the-developer-id-migration).
You create the self-signed identity **once**, and local dev builds sign with it, so Accessibility
persists while you develop.

## 1. Create the `Onecast Self-Signed` identity (once)

Run these in a terminal. They generate a self-signed code-signing certificate and import it into your
login keychain:

```sh
# Generate a self-signed code-signing cert (10-year, codeSigning use).
openssl req -x509 -newkey rsa:2048 -nodes -days 3650 \
  -keyout /tmp/tc-key.pem -out /tmp/tc-cert.pem \
  -subj "/CN=Onecast Self-Signed" \
  -addext "basicConstraints=critical,CA:false" \
  -addext "keyUsage=critical,digitalSignature" \
  -addext "extendedKeyUsage=critical,codeSigning"

# Bundle it as a .p12 (the non-empty password keeps `security import` happy).
openssl pkcs12 -export -inkey /tmp/tc-key.pem -in /tmp/tc-cert.pem \
  -name "Onecast Self-Signed" -out /tmp/tc.p12 -passout pass:onecast

# Import into the login keychain so codesign can use it without prompting.
security import /tmp/tc.p12 -k ~/Library/Keychains/login.keychain-db \
  -P onecast -A -T /usr/bin/codesign

rm -f /tmp/tc-key.pem /tmp/tc-cert.pem /tmp/tc.p12
```

Verify it's there:

```sh
security find-identity -p codesigning | grep "Onecast Self-Signed"
```

Now local builds (Xcode, VS Code F5, `xcodebuild`) sign with it, and you grant Accessibility once.

## Hardened runtime

**Release only**, on both targets: `ENABLE_HARDENED_RUNTIME: YES`, which notarization requires. Debug
must stay without it — hardened runtime turns on library validation, and Xcode's
`Onecast Dev.debug.dylib` is refused at launch because a self-signed identity carries no Team ID for
the loader to match. The flag is not part of the designated requirement, so turning it on costs no
Accessibility grant. Each entitlement in `Onecast/Onecast.entitlements` earns its place:

| Entitlement | Without it |
| --- | --- |
| `com.apple.security.cs.allow-jit` | JavaScriptCore cannot JIT, and every extension command runs on the interpreter |
| `com.apple.security.automation.apple-events` | Every Apple event is refused with `-1743` and no prompt — Get Info, the Finder selection an extension reads, and the System Events–driven system actions all die silently |
| `com.apple.security.device.camera` | The camera prompt never appears and access resolves as denied |
| `com.apple.security.personal-information.calendars` | `requestFullAccessToEvents()` returns `false` in milliseconds with no dialog, and Onecast never appears under System Settings › Calendars |

**A usage string is not enough under the hardened runtime.** `tccd` checks the matching entitlement
*before* it prompts, and without it logs "requires entitlement … but it is missing" and denies on the
spot — no dialog, no error, status still `.notDetermined`. A grant saved before the hardened runtime
arrived keeps working, since `tccd` does not re-check it, which is why this surfaces only on fresh
installs. Adding a protected resource therefore means adding its usage string *and* its entitlement.

`RESOURCE_ENTITLEMENTS` in `Scripts/verify-signature.sh` maps every protected resource's usage string
to its entitlement, including resources Onecast does not use. That grants nothing — only
`Onecast.entitlements` does, and a row whose usage string `Info.plist` doesn't declare is skipped. It
is there so a future feature that adds the usage string but forgets the entitlement fails the release
instead of shipping a prompt that can never appear.

Nothing else is needed: the only `dlopen` is Apple's own IOBluetooth, so library validation is left
on, and `node`, `ray` and shell commands are separate processes it never reaches. Bluetooth has no
hardened-runtime entitlement.

`./Scripts/verify-signature.sh <path-to-.app>` asserts all of this — the runtime flag on the app *and*
on `Contents/Helpers/ClipboardTextHelper` and the Dictation helper bundle, whose identifier must be
the app's plus `.dictation`, an intact nested seal, no `get-task-allow`, and an
entitlement for every usage string `Info.plist` declares. Both release jobs run it before packaging:
a nested binary missing the runtime flag is the most common notarization rejection, and a usage string
missing its entitlement ships a permission that can never be granted. The Dictation helper itself
needs no entitlement: the microphone grant and `audio-input` belong to the app, and the helper only
reads audio from a pipe.

## The Developer ID migration

This fork made the switch with its first release: `release.sh` signs with team `KX3L7SJ2KL`'s
`Developer ID Application` identity and `BundleSignature` pins that team. No self-signed release of
this fork ever shipped, so no installed copy needed the staged hand-over. `BundleSignature` still
accepts the running app's own leaf, which is the only thing a copy installed earlier knows how to check.

The requirement pins the team rather than the certificate, so a Developer ID renewal strands nobody.
It deliberately omits the `notarized` keyword — that resolves a ticket through `syspolicyd` or the
network, and the updater verifies in a cache directory Gatekeeper has never assessed, so an offline
Mac would refuse a bundle the chain already proves is ours.

**The Developer ID identity stays a release-only fact.** It is named on `Scripts/release.sh`'s
`xcodebuild` line and nowhere else: `project.yml` keeps signing with
`Onecast Self-Signed`, so a contributor keeps building with the one they created in §1 — same name,
their own key, never shared. Nothing about local development changes.

**Keep `Onecast Self-Signed` in the login keychain after the switch.** It is the only way to ship a
build that a copy predating the migration could still install.

## Quarantine (separate from signing)

macOS quarantines anything downloaded from the internet, and Gatekeeper blocks a self-signed app
with an "unverified developer" warning. A release is notarized and its app and DMG stapled, so
Gatekeeper passes it offline and neither the cask nor a direct downloader clears anything.
