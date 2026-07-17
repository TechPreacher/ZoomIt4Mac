# Sparkle Updater — Design

**Date:** 2026-07-17
**Status:** Approved

## Problem

ZoomIt4Mac ships via GitHub releases and a Homebrew cask. Users who installed
from the DMG or zip have no way to learn about new versions or update in place.

## Goal

In-app updates the standard macOS way:

- **"Check for Updates…"** item in the status-bar menu (manual check with UI).
- **"Automatically check for updates"** toggle in Settings (on by default).
- Updates download, verify, install, and relaunch in-app via
  [Sparkle 2](https://sparkle-project.org) — the de-facto standard updater
  framework for non-App-Store macOS apps (EdDSA-signed appcast feed).

Rejected alternative: a hand-rolled GitHub-releases API version check
(notify + open browser). Less polish, no in-place install; Sparkle is the
established best practice and the app already has the signing/notarization
infrastructure Sparkle expects.

## Design

### Integration (app target only — zero ZoomItCore changes)

- **SPM dependency** in `project.yml`:

  ```yaml
  packages:
    Sparkle:
      url: https://github.com/sparkle-project/Sparkle
      from: 2.0.0
  ```

  plus `- package: Sparkle` under the `ZoomIt4Mac` target's dependencies,
  then `xcodegen` regen. The app is not sandboxed (`ENABLE_APP_SANDBOX: NO`),
  so no XPC-service setup is needed; hardened runtime is compatible as-is.

- **Info.plist keys** (via `project.yml` `info.properties`):
  - `SUFeedURL`: `https://raw.githubusercontent.com/TechPreacher/ZoomIt4Mac/main/appcast.xml`
  - `SUPublicEDKey`: public half of the one-time-generated EdDSA key pair
  - `SUEnableAutomaticChecks`: `true` — automatic checks on by default,
    suppressing Sparkle's second-launch permission prompt (annoying for a
    menu-bar app); the Settings toggle is the opt-out.

- **`AppDelegate`** owns a single
  `SPUStandardUpdaterController(startingUpdater: true, updaterDelegate: nil, userDriverDelegate: nil)`.
  Sparkle's standard user driver presents all update UI (found/downloading/
  ready-to-relaunch/up-to-date/error) and activates the app itself, so
  `LSUIElement` needs no special handling.

### UI

- **Status menu**: new "Check for Updates…" item between "Settings…" and the
  About separator. `StatusItemController` gains an `onCheckForUpdates`
  closure parameter (matches its existing closure-per-item pattern); the
  wiring in `AppDelegate` calls `updaterController.checkForUpdates(nil)`.
- **Settings window**: new `Section("Updates")` with
  `Toggle("Automatically check for updates")` bound directly to
  `updater.automaticallyChecksForUpdates` (get/set through the model, which
  holds a reference to the updater).

**Deliberate deviation from the core-Settings pattern:** the auto-check flag
is NOT added to the core `Settings` JSON. Sparkle persists
`automaticallyChecksForUpdates` in `UserDefaults` (`SUEnableAutomaticChecks`)
itself; mirroring it in core `Settings` would create two sources of truth
that can drift. Consequently there is no settings migration and no new core
test surface for this feature.

### Release infrastructure

- **One-time setup** (release machine):
  - Run Sparkle's `generate_keys` — the EdDSA private key is stored in the
    login Keychain; the printed public key goes into `project.yml` as
    `SUPublicEDKey`.
- **`scripts/release.sh`** gains an appcast step after notarization:
  - Run Sparkle's `generate_appcast` over the directory containing
    `ZoomIt4Mac-notarized.zip` with
    `--download-url-prefix https://github.com/TechPreacher/ZoomIt4Mac/releases/download/v<version>/`
    so the enclosure URL points at the GitHub release asset.
  - Move/commit the resulting `appcast.xml` to the repo root on `main`
    (the feed URL above serves it via raw.githubusercontent.com).
  - Order of operations at release time: publish the GitHub release (upload
    the zip) **before** pushing the appcast commit — the feed must never
    point at a 404.
- **Version discipline**: Sparkle compares `CFBundleVersion`. Every release
  must bump `CURRENT_PROJECT_VERSION` (monotonically increasing integer)
  alongside `MARKETING_VERSION` in `project.yml`. Currently frozen at
  `1` / `1.0.0`.
- **Homebrew cask**: add `auto_updates true` to the `zoomit4mac` cask in
  `TechPreacher/homebrew-tap` so brew knows the app self-updates (brew then
  skips it in `brew upgrade` by default unless `--greedy`).

## Error handling

- Manual check: Sparkle's standard driver shows its own error alert on
  network failure or a malformed feed, and an "up to date" dialog otherwise.
- Automatic checks fail silently (standard Sparkle behavior).
- EdDSA signature or code-signature mismatch on a downloaded update: Sparkle
  refuses to install (built-in behavior; no custom handling).

## Testing

- No ZoomItCore changes → no new unit tests. Version comparison, feed
  parsing, download verification are Sparkle's tested responsibility.
- Build verification: `xcodebuild build` after `xcodegen` regen with the new
  package dependency (CI must resolve SPM — watch first CI run).
- Interactive smoke: menu shows "Check for Updates…"; clicking it against
  the committed appcast (initially containing only v1.0.0) shows "You're up
  to date"; Settings toggle flips `automaticallyChecksForUpdates` and
  persists across relaunch.
- The full download-install-relaunch loop is only truly testable with a
  published newer version — first real validation happens at the next
  release (e.g. v1.1.0). The release-process doc note in the script header
  covers the steps.

## Out of scope

- Delta updates, update channels (beta), phased rollout.
- Custom update UI (Sparkle standard driver only).
- Mirroring the auto-check flag into core `Settings`.
