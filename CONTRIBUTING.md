# Contributing

Thanks for your interest in ZoomIt4Mac!

## Setup

```sh
brew install xcodegen
xcodegen
open ZoomIt4Mac.xcodeproj   # or build from the CLI, see README
```

`ZoomIt4Mac.xcodeproj` and `ZoomIt4Mac/Info.plist` are generated from `project.yml` — edit `project.yml`, never the generated files, and re-run `xcodegen` after changing it or adding/removing source files.

## Ground rules

- **Keep `ZoomItCore` pure.** The core framework must never import AppKit, and its tests must run headless (no display, no TCC permissions). Logic goes in core; the AppKit shell stays thin.
- **Tests are required for core changes.** Every `ZoomItCore` change ships with Swift Testing coverage, including edge cases. Run the full suite before opening a PR:

  ```sh
  xcodebuild -project ZoomIt4Mac.xcodeproj -scheme ZoomIt4Mac test -destination 'platform=macOS'
  ```
- **Shell changes need a manual check.** UI code (overlays, capture, hotkeys) has no unit tests by design — describe in your PR how you verified the behavior interactively.
- Match the existing code style; prefer small, focused files.

## Feature ideas

Deferred ZoomIt features (break timer, live zoom, screen recording, DemoType, …) are catalogued with implementation notes in [`docs/superpowers/specs/2026-07-14-zoomit4mac-v1-design.md`](docs/superpowers/specs/2026-07-14-zoomit4mac-v1-design.md) — a good place to start.
