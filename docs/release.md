# Release

How a build reaches a user. The local development loop is in [development.md](development.md);
the signing identity itself is in [signing.md](signing.md).

## Packaging a DMG locally

```sh
./Scripts/build-dmg.sh            # -> build/Onecast-<version>.dmg (version from project.yml)
./Scripts/build-dmg.sh 0.5.7      # -> build/Onecast-0.5.7.dmg
```

It builds a Release `Onecast.app` signed with `Onecast Self-Signed` and packs it with an
`/Applications` symlink. An official release is cut with `Scripts/release.sh`, below.

## Signing & Gatekeeper

Releases sign with the `Developer ID Application` identity of team `KX3L7SJ2KL`, with a secure
timestamp, and `Scripts/notarize.sh` notarizes and staples both the app (before it is zipped) and
the DMG, so a download opens without a Gatekeeper prompt. Local builds keep `Onecast Self-Signed`
unless `Signing.local.xcconfig` names a Developer ID. Full details in [signing.md](signing.md).

## How the in-app updater consumes a release

Every release publishes two assets from one build: `Onecast-<version>.dmg`, which people download by
hand and which the cask installs, and `Onecast-<version>.zip`, which the in-app updater installs. The
zip is produced with `ditto -c -k --keepParent --sequesterRsrc` — the only zip that leaves the code
signature verifiable, which matters because the updater refuses any bundle whose signature does not
prove it is ours.

A release publishes two more from the universal build, `Onecast-Universal-<version>.dmg` and
`.zip`, built from the same commit at the same version and bundle id but with both slices. They are
uploaded *after* the thin pair, which keeps the thin zip first in the asset list so builds predating
architecture-aware selection keep choosing it.

Three things a release must keep true, or the updater skips it:

- **It carries a `.zip` asset this Mac can run.** A DMG-only release is not installable and is not
  offered, and an Intel build is offered nothing rather than a thin arm64 zip.
- **The tag parses as `vMAJOR.MINOR.PATCH` or `vMAJOR.MINOR.PATCH-beta.N`,** and agrees with the
  `prerelease` flag. `v0.9.7-sequoia` deliberately parses as neither, which is what keeps beta
  installs off the macOS 15 build.
- **It is not a draft.**

**Both casks declare `auto_updates true`.** That is Homebrew's flag for an app that manages its own
version, and it is what keeps `brew update && brew upgrade` from fighting an app that updated itself:
brew never reports Onecast outdated, never re-downloads it, and never rolls a self-updated copy back.
Removing that line would reintroduce exactly those three problems. See
[features/updates.md](features/updates.md).

## Pull request review

There is no CI workflow. CodeRabbit reviews every PR against `.coderabbit.yaml`: it runs SwiftLint
with `.swiftlint.yml`, annotates the diff and applies the pre-merge checks. It is a reviewer, not a
gate — it neither runs the harnesses nor builds the app, so the whole bar in
[testing.md](testing.md#definition-of-done) is run locally before a PR is opened.

## Releasing

Releases are cut on this Mac, not in CI: there is no release workflow.

```sh
xcrun notarytool store-credentials onecast-notary --apple-id <apple-id> --team-id KX3L7SJ2KL  # once
./Scripts/release.sh 0.2.0
```

`Scripts/release.sh` refuses a dirty tree, a commit not yet on `origin/main` (the tag and the notes
are made on GitHub), a version already released, a missing `Developer ID Application` identity for
team `KX3L7SJ2KL` or a missing notary profile. It then builds two flavors at that version, each into
`build/release/<version>/`: `Onecast-<version>` with `ARCHS=arm64` for Apple silicon, and
`Onecast-Universal-<version>` with `arm64 x86_64` for Intel, since macOS 26 is the last release
that boots on Intel. For each it asserts the slices of every shipping binary (the app,
`ClipboardTextHelper`, `AIToolHelper` and `Onecast Dictation`), runs `verify-signature.sh`, then
notarizes and staples the app before packing the DMG and zip, and notarizes and staples the DMG.
Finally it publishes the GitHub Release tagged `v<version>` with the thin pair first, and bumps both
casks in the tap.

Only stable releases are cut. The app still understands the beta channel (`com.onecast.app.beta`,
`-beta.N` tags), but nothing publishes one.

The app's name reaches `xcodebuild` as `ONECAST_PRODUCT_NAME`, never `PRODUCT_NAME`: a command-line
`PRODUCT_NAME` renames every target, `OnecastPluginKit` included, and the app then cannot import it.

### Release notes

`Scripts/release-notes.sh` composes the release body; `release.sh` runs it just before `gh release create`.
It is safe to run by hand against any tag — it only reads:

```sh
CHANNEL=stable TAG=v0.1.0 ./Scripts/release-notes.sh /tmp/body.md /tmp/discord.md
```

The changelog itself comes from GitHub's own release-notes API, which lists every merged PR with its
author and number — so contributors are credited without anyone maintaining a `CHANGELOG.md`, and
without Conventional Commits. **Nothing is ever committed to this repo**: the tag is created
server-side by `gh release create`, and no release, bot or version-bump commit exists.

Two details the script exists for:

- **The previous tag is picked per channel.** Beta and stable tags interleave on `main` — the same
  commit can carry both — so "the previous release" is only ever right within one channel. A stable
  release therefore spans every beta since the last stable.
- **The body is split by `<!-- onecast:install -->`.** Everything above it is the changelog;
  everything below is the Homebrew and quarantine text, which only a download page needs. The update
  window cuts at that marker — see [features/updates.md](features/updates.md). Full PR URLs are
  shortened to `#304`, which still autolinks on the web and fits a 460pt window.

Its second file is the same changelog cut to Discord's component limit; nothing posts it any more.

### Homebrew tap

`release.sh` rewrites the `version` and `sha256` of the `onecast` and `onecast-universal` casks in
the [`homebrew-onecast`](https://github.com/jhasubhash/homebrew-onecast) tap and pushes, with the
`gh` sign-in it already used for the release. The `sed` is anchored to `^  version` / `^  sha256`,
so a cask's two-space indent on those lines is load-bearing.

Both casks install `Onecast.app` under `com.onecast.app`, so they `conflicts_with` one another and
Homebrew routes each Mac by `depends_on`: `onecast` requires `arch: :arm64`, `onecast-universal`
takes the Intel Macs. The release is notarized, so neither cask strips a quarantine flag.


## Website

`.github/workflows/website.yml` builds `website/` (Next.js static export + Tailwind, with Fumadocs for
the docs section) and deploys it to GitHub Pages at `https://onesyntax.in/onecast/` on every
push to `main` that touches `website/`. Enable it once via
**Settings → Pages → Source = GitHub Actions**.

```sh
cd website && npm install && npm run dev     # local preview
```

The workflow uploads `website/out` — a Next.js export lands there, not in `dist/`. `public/.nojekyll`
must stay: GitHub Pages runs Jekyll, which ignores `_`-prefixed directories, so without it every
asset under `_next/` 404s. See [website/README.md](../website/README.md).
