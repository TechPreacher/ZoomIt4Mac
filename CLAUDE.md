# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Project

ZoomIt4Mac — a native macOS re-implementation of Sysinternals ZoomIt (Windows), in Swift. Menu bar app (`LSUIElement`), macOS 14+, Swift 6.

Implemented: **Zoom** (⌃1, frozen-screen magnify), **Live Zoom** (⌃4, SCStream), **Draw** (⌃2, pen/shapes/colors/undo/boards) with **Type** (T), **Break Timer** (⌃3), rebindable hotkeys, settings + shortcuts-reference windows, ⌘S/⌘C export. Deferred features (screen recording ⌃5, snip, DemoType, blur pens…) are catalogued with implementation notes in `docs/superpowers/specs/2026-07-14-zoomit4mac-v1-design.md`; per-feature specs and plans live under `docs/superpowers/`.

## Commands

```sh
xcodegen   # regenerate ZoomIt4Mac.xcodeproj after editing project.yml or adding/removing files

# Build
xcodebuild -project ZoomIt4Mac.xcodeproj -scheme ZoomIt4Mac build

# Run all tests (Swift Testing, headless — no permissions/display needed)
xcodebuild -project ZoomIt4Mac.xcodeproj -scheme ZoomIt4Mac test -destination 'platform=macOS'

# Run a single test
xcodebuild -project ZoomIt4Mac.xcodeproj -scheme ZoomIt4Mac test -destination 'platform=macOS' \
  -only-testing:ZoomItCoreTests/SessionLifecycleTests/zoomHotkeyStartsCapture
```

`ZoomIt4Mac.xcodeproj` and `ZoomIt4Mac/Info.plist` are **generated** by XcodeGen from `project.yml` and not committed — edit `project.yml`, never the generated files. Release: `scripts/release.sh` (Developer ID + notarization; needs one-time credential setup, see script header).

## Architecture

Two targets with a hard boundary:

- **`ZoomItCore`** (framework, `ZoomItCore/Sources`) — pure Swift, **must never import AppKit**. All logic and state; fully covered by `ZoomItCoreTests` (Swift Testing, headless).
- **`ZoomIt4Mac`** (app, `ZoomIt4Mac/Sources`) — thin AppKit shell + SwiftUI settings. **No unit tests by design** — verified by build + interactive smoke; keep logic out of it.

Event flow is one-directional and everything goes through it:

```
input (hotkeys/keys/mouse/timers) → SessionCoordinator.send(event)
  → SessionStateMachine.handle(event) → [SessionEffect]
  → SessionCoordinator.perform(effect)  (capture, overlays, streams, sounds, render)
  → results fed back in as events (captureCompleted, liveFrameFrozen, breakTick, …)
```

- **`SessionStateMachine`** (core) — single source of mode truth: `.idle`, `.capturing(CaptureTarget)`, `.zoom`, `.liveZoom`, `.draw` (with optional zoom ctx + `fromLiveZoom`), `.type`, `.breakTimer`. Per-state handlers; unknown events return `[]`. Time is always injected via event parameters (`now:`) — **no Date/Timer in core**.
- **`SessionCoordinator`** (shell, MainActor) — owns the machine, executes effects, routes NSEvent input per state, manages overlay windows dict, snapshot store, 1 Hz break tick timer, and the live stream.
- **Coordinate spaces**: annotations live in *image space* (== global screen points of the frozen snapshot); `ZoomGeometry` converts screen↔image; rendering shifts global→window-local inside the zoom transform. Multi-display and negative-origin arrangements are covered by core tests — keep new geometry there.
- **`OverlayContentView`** — one per screen (live zoom: active screen only), draws snapshot/annotations via CG in `draw(_:)`; live zoom renders through a CALayer whose transform comes from the same `ZoomGeometry` math.
- Protocol seams for everything permission-dependent: `Snapshotting`, `LiveStreaming`, `SettingsPersisting` — core logic is tested against fakes.

## Hard-won macOS gotchas (do not "simplify" these away)

- Overlay windows: borderless `NSWindow` **subclass overriding `canBecomeKey`** (stock borderless never becomes key → all keyboard input dies) + **explicitly set `ignoresMouseEvents = false`** (disables per-pixel transparency hit-testing; without it clicks pass through the transparent draw overlay). `sharingType = .none` is the real feedback-loop protection for capture — the SCContentFilter window exclusion usually matches nothing.
- TCC: Screen Recording permission is keyed to the code signature — `DEVELOPMENT_TEAM` in project.yml keeps debug builds stably signed so the grant survives rebuilds. **No Accessibility permission needed** (Carbon `RegisterEventHotKey` + local monitors only; do not introduce CGEventTap without revisiting this).
- Never present a modal (save panel, alert, permission prompt) while `.screenSaver`-level overlays are up — hide/dismiss first, or defer the prompt past the current effect batch.
- LaunchServices caches app icons per bundle path; About panel icon is set explicitly at launch for this reason.
- CI runs an older Xcode/SDK than local: SDK types may lack Sendable annotations there (`@preconcurrency import ScreenCaptureKit`, `nonisolated(unsafe)` IOSurface hop). Watch PR CI after concurrency-adjacent changes.
- Hardened runtime **silently auto-denies** protected devices without the matching entitlement — no TCC prompt, no Privacy-pane entry, `requestAccess` just returns false. The usage string alone is NOT enough: microphone needs `com.apple.security.device.audio-input` (declared in project.yml's `entitlements:` block; camera would need its equivalent).

## Testing expectations

- Every `ZoomItCore` change ships with tests, including edge cases (clamping bounds, NaN, negative-origin displays, undo-on-empty, expiry/pause/adjust semantics, settings-JSON migration from older versions — new `Settings` fields need `decodeIfPresent` + a pinned migration test).
- State-machine tests assert **exact effect arrays** (order matters) alongside states.
- No test may require TCC permissions or a display. Shell behavior changes get an interactive smoke pass instead — describe it in the PR.

## Process notes

- Feature work: spec in `docs/superpowers/specs/`, plan in `docs/superpowers/plans/`, then implement on a `feature/*` branch; PRs to `main` on github.com/TechPreacher/ZoomIt4Mac (switch gh account to `TechPreacher` for PR operations).
- `.superpowers/` is local scratch (gitignored) — session ledgers and reports live there.
