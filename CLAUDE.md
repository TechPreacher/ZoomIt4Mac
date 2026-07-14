# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Project

ZoomIt4Mac — a native macOS re-implementation of Sysinternals ZoomIt (Windows), written in Swift. The repository is currently empty; this file records the agreed direction so the first scaffolding step and all later work stay consistent.

Feature set to mirror (in rough priority order):
1. **Zoom** — full-screen magnification of the live screen, mouse-follow panning, scroll/keyboard zoom level control
2. **Live Zoom** — magnified view that stays live (screen keeps updating) rather than a frozen snapshot
3. **Draw** — annotate on top of the (zoomed or unzoomed) screen: pen, shapes (line, arrow, rectangle, ellipse), colors via keyboard, undo, erase
4. **Type** — type text directly onto the screen overlay
5. **Break Timer** — full-screen countdown with configurable duration and background
6. **Screen Recording** — record the screen/zoomed region (ZoomIt ≥ v6 parity)
7. All features triggered by **global hotkeys**, configurable in a settings window; app lives in the menu bar (no Dock icon)

## Tech decisions

- **Language/UI**: Swift (latest stable), AppKit for the overlay/zoom windows (fine-grained `NSWindow` control is required), SwiftUI for the settings UI. Menu bar presence via `NSStatusItem`, `LSUIElement = YES`.
- **Project format**: Xcode project (`ZoomIt4Mac.xcodeproj`) with an app target and a unit-test target. Core logic (zoom math, annotation model, hotkey parsing, timer state) goes into a separate framework/SPM-style module so it is testable without launching the app.
- **Tests**: Swift Testing (`import Testing`) for new tests. UI-independent logic must be in the testable core module; AppKit-heavy code is kept thin.

## macOS constraints that shape the architecture

These are not optional details — they determine how the app must be structured:

- **No App Sandbox.** Global event taps (`CGEventTap`) and screen capture across all windows are incompatible with sandboxing. Distribution is Developer ID + notarization, not Mac App Store.
- **Permissions (TCC)**: Screen Recording permission (for zoom/live zoom/recording via ScreenCaptureKit) and Accessibility permission (for global hotkeys/event taps). The app must detect missing permissions and guide the user to System Settings; features degrade gracefully, never crash.
- **Screen capture**: use `ScreenCaptureKit` (`SCStream`) — not the deprecated `CGDisplayStream`/`CGWindowListCreateImage`.
- **Overlay windows**: borderless `NSWindow` at `.screenSaver` level, `collectionBehavior` including `.canJoinAllSpaces` and `.fullScreenAuxiliary`, one per screen for multi-display support. Draw/type modes capture all mouse/keyboard input; zoom mode must exclude its own overlay window from capture to avoid feedback loops.
- **Global hotkeys**: Carbon `RegisterEventHotKey` for plain registrations (no Accessibility permission needed) — fall back to `CGEventTap` only where key interception during an active mode requires it.
- **Multi-display and Retina**: all geometry math must handle per-screen `backingScaleFactor` and non-uniform screen arrangements. This is the main source of subtle bugs — cover it in unit tests with simulated screen configurations.

## Commands

Once the Xcode project exists (keep this section updated as scaffolding lands):

```sh
# Build
xcodebuild -project ZoomIt4Mac.xcodeproj -scheme ZoomIt4Mac build

# Run all tests
xcodebuild -project ZoomIt4Mac.xcodeproj -scheme ZoomIt4Mac test

# Run a single test (Swift Testing)
xcodebuild -project ZoomIt4Mac.xcodeproj -scheme ZoomIt4Mac test \
  -only-testing:ZoomIt4MacTests/SomeSuite/someTest
```

Launching the built app from the CLI will trigger TCC permission prompts on first use of capture/hotkey features; permissions granted to a debug build are keyed to the signing identity, so use a stable development signing identity to avoid re-prompting every build.

## Testing expectations

- Every core-module type ships with tests, including edge cases: zoom factor clamping at min/max, coordinate transforms at screen boundaries and across displays with different scale factors, annotation undo stack behavior, timer expiry/pause/resume, hotkey conflict detection.
- Code that requires live TCC permissions or real displays cannot run in CI-style tests — isolate it behind protocols and test the logic against fakes. Do not write tests that depend on Screen Recording permission being granted.
