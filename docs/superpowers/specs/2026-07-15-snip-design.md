# ZoomIt4Mac Snip — Design

Date: 2026-07-15
Status: Approved (brainstorming complete)
Branch: `feature/snip` (off `main` @ 62130a8)

## Goal

Snip (`⌃6`): freeze the screen, drag a rectangular selection, and copy the
selected region to the clipboard as an image — mirroring recent ZoomIt
versions. Holding ⌥ while releasing also offers to save the region as a file.

## Decisions

| Topic | Decision |
|---|---|
| Default hotkey | ⌃6 (keyCode 22), rebindable via the existing hotkey settings |
| Output | Mouse release → clipboard, done. ⌥ held at release → clipboard + save panel (PNG, same `ScreenshotComposer.save` flow as draw mode) |
| Capture model | Reuses the frozen-snapshot capture flow: ⌃6 → `.capturing(.snip)` → `captureCompleted` → `.snip` state with all displays frozen at 1× |
| Selection | Machine-owned: anchor/current points live in a `SnipContext`; drag in any direction; minimum useful size 4×4 pt — smaller release (incl. plain click) clears the selection and stays in snip mode |
| Multi-display | Overlays freeze and dim every display; selection is cropped against the display with the largest overlap; a drag spanning displays is clamped to that display |
| Cancel | Esc, right-click, ⌃6 again, or any other mode hotkey → back to idle, nothing copied |
| Visuals | Frozen snapshot at 1×, 45 % black dim outside the selection, 1 pt white border around it, "W × H" size label (points); crosshair cursor |
| Recording | Orthogonal as always — snipping while recording works; the dim is visible in the recording (same as draw annotations) |
| Modes | ⌃6 inside zoom/live zoom/draw/type/break exits that mode to idle (same convention as ⌃1 inside draw); press ⌃6 again to start snipping |

## Core (`ZoomItCore`)

- **`HotkeyAction.snip`** — default ⌃6 = `KeyCombo(keyCode: 22, modifiers: .control)`; defaults stay conflict-free. Older persisted settings lack the binding; `combo(for:)` already falls back to the default — pinned by a migration test.
- **`CaptureTarget.snip`** — no payload.
- **`SnipContext`** (Equatable, Sendable): `anchor: CGPoint?`, `current: CGPoint?` — global screen points (== image space at 1×).
- **`SessionState.snip(SnipContext)`**.
- **New event `leftMouseUp(CGPoint, optionHeld: Bool)`** — only `.snip` consumes it; every other state ignores it (falls through to `default`).
- **New effect `exportSnip(selection: CGRect, alsoSave: Bool)`**.
- **State machine:**
  - Idle + `hotkey(.snip, _, _)` → `.capturing(.snip)`, `[.captureScreens]`.
  - `.capturing(.snip)`: `captureCompleted` → `.snip(SnipContext())`, `[.showOverlays, .render]`; `captureFailed(.permissionDenied)` → idle, `[.showPermissionGuidance]`; `captureFailed(.captureError)` → idle, `[.notifyCaptureFailure]`; escape → idle (existing).
  - `handleSnip`:
    - `leftMouseDown(p)` → anchor = current = p, `[.render]`.
    - `mouseMoved(p)` → if anchor set, current = p, `[.render]`; otherwise ignored.
    - `leftMouseUp(p, optionHeld)` → requires anchor, else ignored. Normalize rect from anchor→p; if ≥ 4×4 pt: state = idle, `[.exportSnip(selection:alsoSave:), .dismissOverlays]` (export first — dismiss clears the snapshot store). Otherwise clear anchor/current, stay, `[.render]`.
    - `escape` / `rightMouseAction` / any `hotkey` (incl. `.snip`) → idle, `[.dismissOverlays]`.
  - `displayConfigurationChanged` and recording events: covered by the existing pre-dispatch handlers, no snip-specific code.
  - `handleDraw` gains `hotkey(.snip, _, _)` in its exit-to-idle case list (draw enumerates exit hotkeys explicitly; all other handlers already exit via their generic `.hotkey` catch-all).
- **`SnipGeometry`** (new file, pure functions):
  - `normalized(anchor: CGPoint, current: CGPoint) -> CGRect` — any drag direction.
  - `isValidSelection(_ rect: CGRect) -> Bool` — width and height ≥ 4 pt, finite.
  - `pixelCrop(selection: CGRect, displayFrame: CGRect, scale: CGFloat) -> CGRect?` — intersects the selection with the display frame (nil if empty/degenerate), flips Y from bottom-left global points to the CGImage's top-left pixel origin, multiplies by scale.

## Shell

- **Coordinator:**
  - Event routing in `.snip`: local monitors forward `leftMouseDown` → `.leftMouseDown`, `leftMouseDragged` → `.mouseMoved`, `leftMouseUp` → `.leftMouseUp(point, optionHeld: modifierFlags.contains(.option))`. Esc/right-click routing as in other modes.
  - `.exportSnip(selection:alsoSave:)`: pick the `NSScreen` with the largest intersection with the selection; `SnipGeometry.pixelCrop` with that screen's frame and `backingScaleFactor`; `CGImage.cropping(to:)` on the stored snapshot for that display; wrap in `NSImage` (point size); `ScreenshotComposer.copy`. If `alsoSave`: stash the image and present `ScreenshotComposer.save` on the next main-actor tick — `.dismissOverlays` runs in the same effect batch, so the panel never appears under a `.screenSaver` overlay. Crop failure (nil pixel rect / cropping returns nil) → `NSSound.beep()` + log, no clipboard write.
- **OverlayContentView:** `.snip` renders the snapshot 1:1, then a 45 % black dim over the whole screen with the selection rect punched out (`anchor`/`current` present), a 1 pt white stroke around the selection, and a "W × H" label near the selection's lower-right corner (flipped to stay on-screen near edges). Crosshair cursor via `resetCursorRects` while in snip.
- **Menu:** "Snip" item after Start/Stop Recording, key equivalent "6" (display only, consistent with other items). **Settings:** hotkey row for Snip (`keyNames` already maps 22 → "6"). **Shortcuts panel:** new Snip section — drag to select, release to copy, ⌥-release to also save, Esc/right-click cancels. **README:** feature bullet.

## Error handling

- Screen Recording permission missing at ⌃6: existing `.capturing` failure path — deferred prompt + guidance alert.
- Selection entirely outside the chosen display after clamping: beep + log, nothing copied (machine already returned to idle).
- Display change mid-snip: overlays dismissed, back to idle (existing global handler).
- Save panel cancel: clipboard copy already happened; no-op.

## Testing

Core (Swift Testing):
- ⌃6 from idle → `.capturing(.snip)` + `[.captureScreens]`; completed/failed/escape transitions with exact effects.
- Drag lifecycle: down → moved → up produces exact effect arrays; up without anchor ignored; sub-4-pt release clears selection and stays; ⌥ maps to `alsoSave: true`; all four drag directions normalize identically.
- Cancels: escape, right-click, ⌃6, other hotkeys — each → idle + `[.dismissOverlays]`.
- ⌃6 inside zoom/live zoom/draw/type/break exits to idle with that mode's exit effects (draw's added case pinned explicitly).
- Recording phase untouched by all snip events; ⌃5 during `.snip` still toggles recording without leaving snip.
- Defaults conflict-free with ⌃6 added; settings JSON persisted before this feature decodes and yields ⌃6 for `.snip`.
- `SnipGeometry`: negative-direction drags, zero/NaN, retina scale, negative-origin displays, partial and full off-display selections (nil), Y-flip correctness.

Shell: manual smoke — snip on each display, drag all directions, clipboard paste, ⌥-save, tiny-click retains snip mode, Esc/right-click/⌃6 cancel, snip while recording, snip menu item, rebind hotkey.

## Out of scope

Window snipping, freehand/full-screen presets, annotation on the snip before copy, save-to-file without ⌥, floating thumbnail preview (macOS-style), snip while another mode is active without exiting it first.
