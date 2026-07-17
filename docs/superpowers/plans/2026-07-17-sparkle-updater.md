# Sparkle Updater Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** In-app updates via Sparkle 2 — "Check for Updates…" status-menu item, auto-check toggle in Settings, signed appcast feed served from the repo.

**Architecture:** Sparkle 2 as an SPM dependency of the app target only (ZoomItCore untouched). `AppDelegate` owns one `SPUStandardUpdaterController`; the status menu and Settings bind to it. The appcast feed lives at the repo root on `main`, generated and EdDSA-signed by `scripts/release.sh`. Spec: `docs/superpowers/specs/2026-07-17-sparkle-updater-design.md`.

**Tech Stack:** Swift 6, Sparkle 2 (SPM), XcodeGen, AppKit/SwiftUI shell.

## Global Constraints

- ZoomItCore must NOT change in this plan — no new core code, no new core tests.
- Shell (`ZoomIt4Mac` target) has no unit tests by design — verification is build + interactive smoke.
- `ZoomIt4Mac.xcodeproj` and `ZoomIt4Mac/Info.plist` are generated — edit `project.yml` only, then run `xcodegen`.
- Feed URL (exact): `https://raw.githubusercontent.com/TechPreacher/ZoomIt4Mac/main/appcast.xml`
- Auto-check default ON via Info.plist `SUEnableAutomaticChecks: true` (suppresses Sparkle's second-launch permission prompt).
- The auto-check flag is NOT mirrored into core `Settings` JSON (deliberate: Sparkle's UserDefaults is the single source of truth).
- Build: `xcodebuild -project ZoomIt4Mac.xcodeproj -scheme ZoomIt4Mac build`
- Tests: `xcodebuild -project ZoomIt4Mac.xcodeproj -scheme ZoomIt4Mac test -destination 'platform=macOS'`
- Commit messages end with `Co-Authored-By: Claude Fable 5 <noreply@anthropic.com>`.
- GitHub repo is `TechPreacher/ZoomIt4Mac` (public — downloads need no auth; do NOT run `gh auth switch` in this plan, nothing here needs write access to GitHub).

---

### Task 1: Sparkle SPM dependency + feed Info.plist keys

**Files:**
- Modify: `project.yml`

**Interfaces:**
- Consumes: nothing.
- Produces: `import Sparkle` available to the `ZoomIt4Mac` target; Info.plist carries `SUFeedURL` and `SUEnableAutomaticChecks`. Sparkle CLI tools (`generate_keys`, `generate_appcast`) appear under DerivedData's `SourcePackages/artifacts/sparkle/Sparkle/bin/` after resolution — Tasks 2 and 5 use them.

- [ ] **Step 1: Add the package and target dependency to `project.yml`**

Add a top-level `packages:` block (after the `options:` block):

```yaml
packages:
  Sparkle:
    url: https://github.com/sparkle-project/Sparkle
    from: 2.0.0
```

In the `ZoomIt4Mac` target's `dependencies:` list, add the package after the existing ZoomItCore entry:

```yaml
    dependencies:
      - target: ZoomItCore
        embed: true
      - package: Sparkle
```

In the same target's `info.properties`, add (alongside `LSUIElement` etc.):

```yaml
        SUFeedURL: https://raw.githubusercontent.com/TechPreacher/ZoomIt4Mac/main/appcast.xml
        SUEnableAutomaticChecks: true
```

(`SUPublicEDKey` is added in Task 2, once the key exists.)

- [ ] **Step 2: Regenerate and build**

Run:
```sh
xcodegen
xcodebuild -project ZoomIt4Mac.xcodeproj -scheme ZoomIt4Mac build
```
Expected: SPM resolves Sparkle (first build downloads it), BUILD SUCCEEDED. No warnings introduced by the dependency itself.

- [ ] **Step 3: Verify the Sparkle tools landed**

Run:
```sh
find ~/Library/Developer/Xcode/DerivedData/ZoomIt4Mac-*/SourcePackages/artifacts -name generate_appcast -o -name generate_keys
```
Expected: both binaries listed (under `.../artifacts/sparkle/Sparkle/bin/`).

- [ ] **Step 4: Commit**

```sh
git add project.yml
git commit -m "Add Sparkle 2 dependency and update feed configuration

Co-Authored-By: Claude Fable 5 <noreply@anthropic.com>"
```

---

### Task 2: EdDSA signing keys + public key in Info.plist

**Files:**
- Modify: `project.yml`

**Interfaces:**
- Consumes: Sparkle `generate_keys` tool from Task 1.
- Produces: EdDSA private key in the login Keychain (item "Private key for signing Sparkle updates"); `SUPublicEDKey` in Info.plist. Task 5's `generate_appcast` signs with this key automatically.

- [ ] **Step 1: Generate the key pair**

Run:
```sh
SPARKLE_BIN=$(dirname "$(find ~/Library/Developer/Xcode/DerivedData/ZoomIt4Mac-*/SourcePackages/artifacts -name generate_keys | head -1)")
"$SPARKLE_BIN/generate_keys"
```
Expected output contains a line like `SUPublicEDKey` with a 44-char base64 value, and the private key is stored in the login Keychain. If a key already exists, the tool prints the existing public key — use that.

If the Keychain write fails (sandboxed shell), report BLOCKED — the human must run `generate_keys` once in a normal terminal and paste the public key.

- [ ] **Step 2: Add the public key to `project.yml`**

In the `ZoomIt4Mac` target's `info.properties`, add (replace `<PUBLIC_KEY_FROM_STEP_1>` with the actual base64 value):

```yaml
        SUPublicEDKey: <PUBLIC_KEY_FROM_STEP_1>
```

- [ ] **Step 3: Regenerate, build, and verify the key is in the built Info.plist**

Run:
```sh
xcodegen
xcodebuild -project ZoomIt4Mac.xcodeproj -scheme ZoomIt4Mac build
APP=$(xcodebuild -project ZoomIt4Mac.xcodeproj -scheme ZoomIt4Mac -showBuildSettings build 2>/dev/null | awk -F' = ' '/ BUILT_PRODUCTS_DIR/{print $2; exit}')
/usr/libexec/PlistBuddy -c "Print :SUPublicEDKey" "$APP/ZoomIt4Mac.app/Contents/Info.plist"
/usr/libexec/PlistBuddy -c "Print :SUFeedURL" "$APP/ZoomIt4Mac.app/Contents/Info.plist"
```
Expected: BUILD SUCCEEDED; PlistBuddy prints the public key and the feed URL.

- [ ] **Step 4: Commit**

```sh
git add project.yml
git commit -m "Add Sparkle EdDSA public key

Co-Authored-By: Claude Fable 5 <noreply@anthropic.com>"
```

---

### Task 3: Updater controller + "Check for Updates…" menu item

**Files:**
- Modify: `ZoomIt4Mac/Sources/AppDelegate.swift`
- Modify: `ZoomIt4Mac/Sources/StatusItemController.swift`

**Interfaces:**
- Consumes: Sparkle module from Task 1.
- Produces: `AppDelegate.updaterController: SPUStandardUpdaterController` (Task 4 passes `updaterController.updater` into the settings window); `StatusItemController.init` gains `onCheckForUpdates: @escaping () -> Void` between `onShortcuts` and `onSettings`' neighbor — exact position: after `onSettings`.

- [ ] **Step 1: Add the updater controller to `AppDelegate`**

In `ZoomIt4Mac/Sources/AppDelegate.swift`, add `import Sparkle` after `import AppKit`, and add this property after `private let settingsStore ...`:

```swift
    // Sparkle: created at init so the updater starts with the app and can
    // schedule its background checks (SUEnableAutomaticChecks defaults on).
    private let updaterController = SPUStandardUpdaterController(
        startingUpdater: true,
        updaterDelegate: nil,
        userDriverDelegate: nil
    )
```

- [ ] **Step 2: Add the menu item to `StatusItemController`**

In `ZoomIt4Mac/Sources/StatusItemController.swift`:

Add a stored closure after `private let onSettings: () -> Void`:

```swift
    private let onCheckForUpdates: () -> Void
```

Add an init parameter after `onSettings: @escaping () -> Void,`:

```swift
        onCheckForUpdates: @escaping () -> Void
```

(and assign `self.onCheckForUpdates = onCheckForUpdates` alongside the other assignments, before `super.init()`).

In the menu construction, after the `Settings…` line and before the existing `.separator()` that precedes About:

```swift
        menu.addItem(makeItem("Check for Updates…", action: #selector(checkForUpdatesTapped), key: ""))
```

Add the selector next to the other `@objc` handlers:

```swift
    @objc private func checkForUpdatesTapped() { onCheckForUpdates() }
```

- [ ] **Step 3: Wire it in `AppDelegate`**

In the `StatusItemController(...)` construction, add after `onSettings: { settingsWindow.show() }`:

```swift
            onCheckForUpdates: { [weak self] in self?.updaterController.checkForUpdates(nil) }
```

- [ ] **Step 4: Build**

Run:
```sh
xcodebuild -project ZoomIt4Mac.xcodeproj -scheme ZoomIt4Mac build
```
Expected: BUILD SUCCEEDED, no new warnings.

- [ ] **Step 5: Commit**

```sh
git add ZoomIt4Mac/Sources/AppDelegate.swift ZoomIt4Mac/Sources/StatusItemController.swift
git commit -m "Add Sparkle updater with Check for Updates menu item

Co-Authored-By: Claude Fable 5 <noreply@anthropic.com>"
```

---

### Task 4: Settings "Updates" section

**Files:**
- Modify: `ZoomIt4Mac/Sources/SettingsWindow.swift`
- Modify: `ZoomIt4Mac/Sources/AppDelegate.swift` (SettingsWindowController call site)

**Interfaces:**
- Consumes: `AppDelegate.updaterController.updater` (type `SPUUpdater`) from Task 3.
- Produces: `SettingsWindowController.init(store:updater:onApply:)` and `SettingsModel.init(store:updater:onApply:)` — both gain `updater: SPUUpdater` as the second parameter.

- [ ] **Step 1: Thread the updater through the settings model**

In `ZoomIt4Mac/Sources/SettingsWindow.swift`, add `import Sparkle` after `import ServiceManagement`.

In `SettingsModel`: add a stored property after `private let store: SettingsStore`:

```swift
    private let updater: SPUUpdater
```

Change the init to accept it (second parameter) and assign:

```swift
    init(store: SettingsStore, updater: SPUUpdater, onApply: @escaping (ZoomItCore.Settings) -> Void) {
        self.store = store
        self.updater = updater
        self.onApply = onApply
        self.settings = store.load()
        self.launchAtLogin = SMAppService.mainApp.status == .enabled
    }
```

Add accessors after `setLaunchAtLogin` (Sparkle persists the flag in UserDefaults itself — deliberately NOT mirrored into core `Settings`, see the design spec):

```swift
    var automaticallyChecksForUpdates: Bool { updater.automaticallyChecksForUpdates }

    func setAutomaticallyChecksForUpdates(_ enabled: Bool) {
        updater.automaticallyChecksForUpdates = enabled
        objectWillChange.send()
    }
```

- [ ] **Step 2: Thread the updater through the window controller**

In `SettingsWindowController`: add a stored property after `private let store: SettingsStore`:

```swift
    private let updater: SPUUpdater
```

Change its init to:

```swift
    init(store: SettingsStore, updater: SPUUpdater, onApply: @escaping (ZoomItCore.Settings) -> Void) {
        self.store = store
        self.updater = updater
        self.onApply = onApply
    }
```

and the model construction inside `show()` to:

```swift
            let model = SettingsModel(store: store, updater: updater, onApply: onApply)
```

- [ ] **Step 3: Add the Updates section to the form**

In `SettingsView`'s `Form`, after the `Section("Recording") { ... }` block and before the unlabeled `Section { Toggle("Launch at login" ... } ` block:

```swift
            Section("Updates") {
                Toggle("Automatically check for updates", isOn: Binding(
                    get: { model.automaticallyChecksForUpdates },
                    set: { model.setAutomaticallyChecksForUpdates($0) }
                ))
            }
```

- [ ] **Step 4: Update the `AppDelegate` call site**

In `ZoomIt4Mac/Sources/AppDelegate.swift`, change the settings window construction to:

```swift
        let settingsWindow = SettingsWindowController(store: settingsStore, updater: updaterController.updater) { [weak self] newSettings in
            self?.coordinator?.applySettings(newSettings)
            self?.applyHotkeys(newSettings)
        }
```

- [ ] **Step 5: Build**

Run:
```sh
xcodebuild -project ZoomIt4Mac.xcodeproj -scheme ZoomIt4Mac build
```
Expected: BUILD SUCCEEDED, no new warnings.

- [ ] **Step 6: Commit**

```sh
git add ZoomIt4Mac/Sources/SettingsWindow.swift ZoomIt4Mac/Sources/AppDelegate.swift
git commit -m "Add automatic update check toggle to settings

Co-Authored-By: Claude Fable 5 <noreply@anthropic.com>"
```

---

### Task 5: Initial appcast.xml for v1.0.0

**Files:**
- Create: `appcast.xml` (repo root)

**Interfaces:**
- Consumes: EdDSA key from Task 2; `generate_appcast` tool from Task 1.
- Produces: signed `appcast.xml` at repo root containing the v1.0.0 entry — the live feed once this branch merges to `main`.

- [ ] **Step 1: Download the released v1.0.0 zip**

Run (public repo, no auth):
```sh
mkdir -p build/appcast
gh release view v1.0.0 --repo TechPreacher/ZoomIt4Mac --json assets --jq '.assets[].name'
```
Expected: the release's asset names. Download the notarized app zip asset (pick the `.zip` asset; if several, the app zip — not dSYMs):
```sh
gh release download v1.0.0 --repo TechPreacher/ZoomIt4Mac --pattern '*.zip' --dir build/appcast
mv build/appcast/*.zip build/appcast/ZoomIt4Mac-1.0.0.zip
```

- [ ] **Step 2: Generate the signed appcast**

Run:
```sh
SPARKLE_BIN=$(dirname "$(find ~/Library/Developer/Xcode/DerivedData/ZoomIt4Mac-*/SourcePackages/artifacts -name generate_appcast | head -1)")
"$SPARKLE_BIN/generate_appcast" build/appcast \
  --download-url-prefix "https://github.com/TechPreacher/ZoomIt4Mac/releases/download/v1.0.0/"
cp build/appcast/appcast.xml appcast.xml
```
Expected: `appcast.xml` at repo root with one `<item>` — `sparkle:version` = 1 (the shipped CFBundleVersion), `sparkle:shortVersionString` = 1.0.0, an `edSignature` attribute on the enclosure, and enclosure URL `https://github.com/TechPreacher/ZoomIt4Mac/releases/download/v1.0.0/ZoomIt4Mac-1.0.0.zip`.

Note: that exact asset name may not exist on the v1.0.0 release — acceptable: no client ever downloads the entry matching its own current version; the entry exists so v1.0.0 clients see "you're up to date". From the next release on, `scripts/release.sh` (Task 6) produces correctly named assets.

- [ ] **Step 3: Sanity-check the feed is valid XML**

Run:
```sh
xmllint --noout appcast.xml
```
Expected: no output (valid XML). `xmllint` ships with macOS.

- [ ] **Step 4: Commit**

```sh
git add appcast.xml
git commit -m "Add Sparkle appcast with v1.0.0 entry

Co-Authored-By: Claude Fable 5 <noreply@anthropic.com>"
```

---

### Task 6: Appcast generation in release script

**Files:**
- Modify: `scripts/release.sh`

**Interfaces:**
- Consumes: conventions from Task 5 (versioned zip name, download-url-prefix form).
- Produces: release.sh that regenerates + signs `appcast.xml` for each release.

- [ ] **Step 1: Extend the one-time-setup header comment**

In `scripts/release.sh`, extend the header comment block (after the notarytool line) to:

```bash
#   3. Sparkle EdDSA key in the login keychain (one-time: run generate_keys
#      from the Sparkle SPM artifacts; public key lives in project.yml).
#
# Per release:
#   - Bump MARKETING_VERSION *and* CURRENT_PROJECT_VERSION in project.yml
#     (Sparkle compares CFBundleVersion — it must increase every release).
#   - Publish the GitHub release with build/ZoomIt4Mac-<version>.zip attached
#     BEFORE pushing the appcast.xml commit to main (the feed must never
#     point at a missing asset).
#   - Homebrew cask: zoomit4mac cask in TechPreacher/homebrew-tap should
#     declare `auto_updates true` (the app self-updates via Sparkle).
```

- [ ] **Step 2: Add the appcast step at the end of the script**

Append before the final `echo`:

```bash
# Sparkle appcast: sign this build and regenerate the feed (single latest
# entry — Sparkle only needs the newest version). Signing uses the EdDSA
# private key from the login keychain.
VERSION=$(sed -n 's/^ *MARKETING_VERSION: *//p' project.yml | tr -d '"' | head -1)
SPARKLE_BIN=$(dirname "$(find "$HOME/Library/Developer/Xcode/DerivedData" -path '*SourcePackages/artifacts/*' -name generate_appcast 2>/dev/null | head -1)")
APPCAST_DIR=build/appcast
rm -rf "$APPCAST_DIR"
mkdir -p "$APPCAST_DIR"
cp build/ZoomIt4Mac-notarized.zip "$APPCAST_DIR/ZoomIt4Mac-$VERSION.zip"
"$SPARKLE_BIN/generate_appcast" "$APPCAST_DIR" \
  --download-url-prefix "https://github.com/TechPreacher/ZoomIt4Mac/releases/download/v$VERSION/"
cp "$APPCAST_DIR/appcast.xml" appcast.xml
```

and change the final `echo` to:

```bash
echo "Done: build/ZoomIt4Mac-notarized.zip, build/ZoomIt4Mac.dmg, build/appcast/ZoomIt4Mac-$VERSION.zip"
echo "Next: publish the GitHub release with ZoomIt4Mac-$VERSION.zip attached, THEN commit + push appcast.xml to main."
```

- [ ] **Step 3: Syntax-check the script**

Run:
```sh
bash -n scripts/release.sh
```
Expected: no output (parses cleanly). Do NOT run the release script itself.

- [ ] **Step 4: Commit**

```sh
git add scripts/release.sh
git commit -m "Generate Sparkle appcast in release script

Co-Authored-By: Claude Fable 5 <noreply@anthropic.com>"
```

---

### Task 7: Full test run + interactive smoke

**Files:** none (verification only).

- [ ] **Step 1: Full suite**

Run:
```sh
xcodebuild -project ZoomIt4Mac.xcodeproj -scheme ZoomIt4Mac test -destination 'platform=macOS'
```
Expected: all tests pass (core untouched by this plan — count unchanged).

- [ ] **Step 2: Interactive smoke (needs the user)**

Ask the user to run this pass and report back:

1. Launch the app. Status menu shows "Check for Updates…" between Settings… and About.
2. Click it. Because the feed URL 404s until this branch merges to `main`, Sparkle shows an "update error / cannot check" alert — that alert appearing IS the pass criterion pre-merge (proves wiring + feed lookup). Post-merge, the same click must show "You're up to date."
3. Settings → Updates: toggle "Automatically check for updates" off, quit, relaunch, reopen Settings — toggle still off. Turn it back on.
4. No Sparkle permission prompt appears on second launch (SUEnableAutomaticChecks suppresses it).

- [ ] **Step 3: Record smoke results in the PR description**

Note: feed goes live when the branch merges to `main` (raw.githubusercontent.com serves `appcast.xml` from `main`). Full download-install-relaunch loop is first validated at the next real release.
