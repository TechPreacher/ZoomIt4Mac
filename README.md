<p align="center">
  <img src="Design/icon-1024.png" width="160" alt="ZoomIt4Mac icon">
</p>

<h1 align="center">ZoomIt4Mac</h1>

<p align="center">
  A native macOS re-implementation of the Sysinternals
  <a href="https://learn.microsoft.com/sysinternals/downloads/zoomit">ZoomIt</a>
  presentation tool — screen zoom and annotation from your menu bar.
</p>

<p align="center">
  <img alt="Platform" src="https://img.shields.io/badge/platform-macOS%2014%2B-blue">
  <img alt="Swift" src="https://img.shields.io/badge/Swift-6-orange">
  <img alt="License" src="https://img.shields.io/badge/license-MIT-green">
</p>

---

## Features

- **Zoom** (`⌃1`) — freezes the screen and smoothly zooms in on the mouse position. Move the mouse to pan (every screen edge reachable at any zoom level), scroll / pinch / `↑` `↓` to change magnification (1×–8×). Right-click, Esc, or `⌃1` exits.
- **Live Zoom** (`⌃4`) — like Zoom, but the magnified screen keeps updating (video, demos). Same pan/zoom controls; left-click freezes the current frame for annotation, Esc returns to live. Active display only.
- **Draw** (`⌃2`, or left-click while zoomed) — annotate the screen or the frozen zoomed image:

  | Input | Action |
  |---|---|
  | drag | freehand pen |
  | `⇧`-drag / `⌃⇧`-drag | straight line / arrow |
  | `⌃`-drag / hold `Tab`+drag | rectangle / ellipse |
  | `R` `G` `B` `O` `Y` `P` | pen color |
  | `⌘`-scroll | pen width |
  | `⌘Z` or right-click | undo |
  | `E` | erase all |
  | `W` / `K` | whiteboard / blackboard |
  | `⌘S` / `⌘C` | save PNG / copy to clipboard |
  | `Esc` | back to zoom, or exit |

  In plain draw mode the exported PNG has a transparent background.
- **Type** (`T` while drawing) — click to place the caret and type on screen. `⌘+` / `⌘−` adjust font size, Esc finishes.
- **Break Timer** (`⌃3`) — full-screen countdown for presentation breaks. `Space` pauses, `↑` `↓` or scroll adjusts by a minute, Esc ends. Configurable duration (1–99 min), position, opacity, and background (solid black, faded desktop, or an image); optional sound and elapsed-time display on expiry.
- **Screen Recording** (`⌃5`) — records the active display to `~/Movies/ZoomIt4Mac/` (H.264 .mp4, revealed in Finder when done). A brief on-screen notice announces the start (press `⌃5` again during it to cancel); capture begins after it disappears, so the notice is never in your video. Your zoom and draw annotations are part of the recording. Optional microphone and system-audio capture (Settings → Recording); works while any other mode is active.
- **Settings** — rebind the hotkeys (with conflict detection), default zoom level, pen defaults, launch at login.

Menu bar app (`LSUIElement`) — no Dock icon.

## Permissions

Zoom and Live Zoom require **Screen Recording** permission (System Settings → Privacy & Security → Screen & System Audio Recording). Draw and Type work without it. No Accessibility permission is required. Recording with the microphone enabled additionally asks for **Microphone** permission (optional — recordings proceed without it if denied).

## Building

Requires Xcode 16+ and [XcodeGen](https://github.com/yonaskolb/XcodeGen):

```sh
brew install xcodegen
xcodegen                # generates ZoomIt4Mac.xcodeproj (not committed)
xcodebuild -project ZoomIt4Mac.xcodeproj -scheme ZoomIt4Mac build
xcodebuild -project ZoomIt4Mac.xcodeproj -scheme ZoomIt4Mac test -destination 'platform=macOS'
```

## Architecture

- **`ZoomItCore`** — pure-Swift framework: session state machine, zoom geometry, annotation model, hotkey/settings models. No AppKit; fully covered by headless [Swift Testing](https://developer.apple.com/documentation/testing) tests.
- **`ZoomIt4Mac`** — thin AppKit shell: overlay windows, ScreenCaptureKit capture, Carbon global hotkeys, SwiftUI settings.

Design and plan documents live under [`docs/`](docs/).

## Release

`scripts/release.sh` archives, exports with Developer ID, notarizes, and staples a distributable zip (see the script header for one-time credential setup).

## Acknowledgements

ZoomIt is a [Sysinternals](https://learn.microsoft.com/sysinternals/) tool by Mark Russinovich; ZoomIt and Sysinternals are trademarks of Microsoft Corporation. This project is an independent re-implementation for macOS and is not affiliated with or endorsed by Microsoft.

## License

[MIT](LICENSE)
