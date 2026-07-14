# ZoomIt4Mac

A native macOS re-implementation of the Sysinternals [ZoomIt](https://learn.microsoft.com/sysinternals/downloads/zoomit) presentation tool. Menu bar app, macOS 14+.

## Features (v1)

- **Zoom** (⌃1): freeze the screen and magnify 1×–8×. Mouse pans, scroll/pinch/↑↓ zooms. Left-click to annotate the zoomed image, right-click or Esc to exit.
- **Draw** (⌃2): annotate the screen. Drag = pen; ⇧ line, ⌃⇧ arrow, ⌃ rectangle, Tab-held ellipse. Colors R/G/B/O/Y/P. ⌘Z or right-click undo, E erase, W/K white/blackboard, ⌘-scroll pen width, ⌘S save PNG, ⌘C copy.
- **Type** (T while drawing): click to place the caret and type. ⌘+/⌘− font size, Esc done.
- Hotkeys rebindable in Settings; launch-at-login optional.

## Permissions

Zoom needs **Screen Recording** permission (System Settings → Privacy & Security). Draw and Type work without it. No Accessibility permission required.

## Building

```sh
brew install xcodegen
xcodegen
xcodebuild -project ZoomIt4Mac.xcodeproj -scheme ZoomIt4Mac build
xcodebuild -project ZoomIt4Mac.xcodeproj -scheme ZoomIt4Mac test -destination 'platform=macOS'
```

## Release

`scripts/release.sh` archives, exports with Developer ID, notarizes, and staples (see script header for one-time credential setup).
