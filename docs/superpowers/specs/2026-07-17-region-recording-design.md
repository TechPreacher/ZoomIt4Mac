# Region Recording — Design

**Date:** 2026-07-17
**Status:** Approved

## Problem

Screen Recording (⌃5) always captures the full active display. Recording a
single window-sized area — a demo, a terminal, one app — wastes pixels,
bitrate, and viewer attention.

## Goal

**Region Recording (⌃⇧5, rebindable):** freeze the screen, drag-select an
area (identical interaction to Snip/OCR Snip), then record exactly that
region — with the existing recording notice, codec (HEVC/H.264 + tuned
bitrate, which auto-scales down with region size), microphone/system-audio
settings, and output location. A thin border frame marks the recorded
bounds for the duration of the recording and is never part of the
recording itself. ⌃⇧5 while recording stops it (same toggle semantics
as ⌃5).

## Design

### Core (`ZoomItCore`)

- **`HotkeyAction.regionRecord`** — default
  `KeyCombo(keyCode: 23, modifiers: [.control, .shift])` (⌃⇧5). Conflict
  detection automatic via `allCases`; persisted hotkey JSON falls back to
  the default for the missing key (pinned test, same pattern as `ocrSnip`).
- **`SnipKind.record`** and **`CaptureTarget.regionRecord`** — the third
  snip kind. Hotkey handling in idle:
  - `recordingPhase == .off` → `.capturing(.regionRecord)`,
    `[.captureScreens]`; `captureCompleted` →
    `.snip(SnipContext(kind: .record))`, `[.showOverlays, .render]`.
  - `recordingPhase == .pending` → cancel: phase `.off`,
    `[.dismissRecordingNotice]` (mirrors ⌃5 cancel-during-notice).
  - `recordingPhase == .active` → stop: phase `.off`, `[.stopRecording]`.
  - From active modes (zoom/draw/…): the generic in-mode hotkey handling
    exits the mode, exactly as the snip hotkey does today.
  - Capture failure routes identical to snip (`.showPermissionGuidance` /
    `.notifyCaptureFailure`).
- **`RecordingPhase.pending` gains a payload:** `.pending(region: CGRect?)`.
  Full-display ⌃5 produces `.pending(region: nil)`; region selection
  produces `.pending(region: selection)` (global screen points). The
  region travels through the notice wait in the machine — no side-channel
  state. Existing tests touching `.pending` update mechanically.
- **`SessionEffect.startRecording` gains a payload:**
  `.startRecording(region: CGRect?)` — nil means full display (today's
  behavior). `.recordingNoticeElapsed` on `.pending(let region)` →
  `.active`, `[.dismissRecordingNotice, .startRecording(region: region)]`.
- **Selection release** (`.record` kind, valid selection): phase becomes
  `.pending(region: selection)`, state `.idle`, effects
  `[.dismissOverlays, .showRecordingNotice]`. `optionHeld` ignored.
- **Minimum region: 32 pt per edge** for `.record` (image/text keep 4 pt) —
  guards against degenerate encoder sizes. A smaller drag clears the
  selection and stays in `.record` snip mode for retry (kind preserved),
  identical to the other kinds' retry behavior.
- **`RecordingGeometry`** (new file, pure, tested) —
  - `sourceRect(selection: CGRect, displayFrame: CGRect) -> CGRect?`:
    converts a global AppKit selection (bottom-left origin) to
    ScreenCaptureKit's `sourceRect` space (display-relative points,
    top-left origin), clamped to the display; nil when the clamped rect
    is empty.
  - `outputPixelSize(sourceRect: CGRect, scale: CGFloat) -> CGSize`:
    pixel dimensions rounded DOWN to even integers (hardware encoders
    require even dimensions), floored at 2×2.
  - Tests: Retina scale, negative-origin display arrangements, selection
    partially/fully outside the display, odd-pixel rounding.

### Shell (`ZoomIt4Mac`)

- **`ScreenRecording.start`** gains `region: CGRect?` — display-relative
  top-left-origin points, already converted by the coordinator. In
  `ScreenRecorderController`: `config.sourceRect = region` and
  `config.width/height` from `RecordingGeometry.outputPixelSize`; the
  `RecordingWriter` gets the same (even) pixel size, so
  `averageBitRate(width:height:frameRate:)` automatically scales the
  bitrate to the region. `region == nil` → full display exactly as today.
- **`SessionCoordinator`** performs `.startRecording(region:)`:
  - nil region → current behavior (display under the mouse).
  - non-nil → display with max selection overlap (same `overlapArea` logic
    as snip export), convert via `RecordingGeometry.sourceRect`, pass to
    the recorder; on conversion failure beep + `.recordingFailed` path.
  - Shows the region frame while recording; hides it on stop, failure, and
    mid-recording stream death (the existing salvage path).
  - The recording notice is reused; its stop-combo label shows the
    ⌃⇧5 binding (`combo(for: .regionRecord)`) for region recordings.
- **`RecordingFrameWindow`** (new file) — borderless, non-activating,
  click-through panel that strokes the recorded bounds (drawn just outside
  the selection so content is not covered). **`sharingType = .none`** —
  the window server omits it from all captures, so the frame is never in
  the recording (stronger guarantee than the overlays' deliberate
  `.readOnly`).
- **UI surfaces** — status-menu item "Record Region" (⌃⇧5; same toggle
  semantics as the hotkey — activating it while recording stops), Settings
  hotkey row "Record Region", Shortcuts window global row
  "Record Region — record a screen area". Mic/system-audio/codec settings
  apply unchanged (same Settings → Recording section).

## Error handling

- Permission/capture failure entering selection: identical to snip.
- Geometry conversion failure (selection entirely off-display after
  clamping): beep + recording aborts via the existing failed path.
- Mid-recording stream death: existing salvage (partial file revealed) +
  frame hidden.
- Display configuration change: existing behavior (stops recording /
  cancels notice) — covered by existing tests, extended for the region
  payload.

## Testing

- **Core (exact effect arrays):** ⌃⇧5 idle → capture → `.record` snip;
  release ≥32 pt → `[.dismissOverlays, .showRecordingNotice]` +
  `.pending(region:)`; notice elapsed → `[.dismissRecordingNotice,
  .startRecording(region:)]`; ⌃⇧5 during notice cancels; ⌃⇧5 while active
  stops; ⌃5 still produces `.pending(region: nil)` /
  `.startRecording(region: nil)`; sub-32 pt drag retries with kind
  preserved; 4 pt minimum unchanged for image/text kinds; hotkey default +
  JSON fallback; all `RecordingGeometry` edge cases.
- **Shell (build + smoke):** region recording produces a file of the
  region's size (even dims); frame visible during recording and absent
  from the file; mic/system audio + codec respected; ⌃5 full-display
  unchanged; ⌃⇧5 stop works; Esc during selection cancels cleanly.

## Out of scope

- Moving/resizing the region mid-recording
- Window-picker recording (record a specific window)
- Multiple simultaneous regions
- Remembering the last region

## Branching

Builds on `SnipKind` from the OCR Snip branch (PR #12, unmerged):
`feature/region-recording` branches off `feature/ocr-snip`; the PR is
stacked and targets `main` after #12 merges.
