# OCR Snip — Design

**Date:** 2026-07-17
**Status:** Approved

## Problem

Snip (⌃6) copies a screen region as an image. Text inside that region —
error messages, terminal output, code on a slide — has to be retyped.

## Goal

**OCR Snip (⌃⌥6, rebindable):** freeze the screen, drag-select a region
(identical interaction to Snip), recognize the text in it with Apple's
on-device Vision framework, and put the recognized text on the clipboard.
A transient HUD reports the outcome ("N lines copied" / "No text found").

Constraints honored by construction:
- **Entirely on-device** — `VNRecognizeTextRequest` runs locally; no network.
- **No new permissions** — the region is cropped from the frozen snapshot
  that Snip already captures under the existing Screen Recording grant.

## Design

### Core (`ZoomItCore`) — snip flow parameterized by kind

- **`HotkeyAction.ocrSnip`** — new case; default combo
  `KeyCombo(keyCode: 22, modifiers: [.control, .option])` (⌃⌥6).
  Conflict detection covers it automatically via `allCases`. Persisted
  hotkey JSON needs no migration (decoder falls back to the default for
  missing keys) — pinned fallback test added anyway, matching the existing
  `settingsPersistedBeforeSnipFallBackToCtrl6` pattern.
- **`CaptureTarget.ocrSnip`** — new capture target; hotkey handler maps
  `.ocrSnip` → `.capturing(.ocrSnip)` exactly as `.snip` does.
- **`SnipKind`** — new enum `{ image, text }`. `SnipContext` gains
  `kind: SnipKind = .image`. `captureCompleted` with `.ocrSnip` enters
  `.snip(SnipContext(kind: .text))`; all drag / normalize / minimum-size
  logic in `handleSnip` is shared — zero duplication.
- **`SessionEffect.recognizeText(selection: CGRect)`** — new effect. On
  `leftMouseUp` with a valid selection, kind `.text` emits
  `[.recognizeText(selection:), .dismissOverlays]`; the `optionHeld` flag
  is ignored for text (no save-to-file variant — YAGNI). Kind `.image`
  emits `[.exportSnip(selection:alsoSave:), .dismissOverlays]` unchanged.
  Invalid (<4 pt edge) selections cancel identically for both kinds.

### Shell (`ZoomIt4Mac`)

- **`TextRecognitionService`** (new file) — wraps Vision:
  `VNRecognizeTextRequest` with `.accurate` recognition level,
  `automaticallyDetectsLanguage = true`, `usesLanguageCorrection = true`,
  executed on a background queue; completion hops to the main actor with
  `[String]` (top-candidate strings of the observations, Vision's natural
  top-to-bottom order).
- **`SessionCoordinator`** — performs `.recognizeText`: the display-overlap
  + Retina pixel-crop logic currently inside `exportSnip()` is extracted
  into a shared private helper used by both effects; the cropped `CGImage`
  goes to `TextRecognitionService`; on completion the lines are joined with
  `\n`, written to `NSPasteboard.general` (`.string`), and the HUD shows.
- **HUD** — `SnipNoticeWindow` (new file, modeled on the existing
  `RecordingNoticeWindow` pattern): small non-activating panel, text
  "N lines copied" (singular handled) or "No text found", auto-fades after
  ~1.5 s. Shown only after `.dismissOverlays` has executed — never a
  modal or panel while `.screenSaver`-level overlays are up.
- **UI surfaces** — status-menu item "OCR Snip" below "Snip";
  Settings hotkey row "OCR Snip"; Shortcuts window global row
  "OCR Snip — copy text in a region". The "While snipping" section already
  describes drag/release/Esc, which applies to both kinds (the ⌥-release
  save row remains image-snip-only and is labeled as such if ambiguous).

## Error handling

- Vision error or zero observations → HUD "No text found". No beep — the
  HUD is the single feedback channel.
- Capture failure → existing `.captureFailed` path (unchanged).
- Selection too small → silent cancel, same as image snip.

## Testing

- **Core (headless, exact effect arrays):** ⌃⌥6 hotkey → `.capturing(.ocrSnip)`;
  captureCompleted → `.snip(kind: .text)`; drag + release →
  `[.recognizeText(normalized), .dismissOverlays]`; ⌥-release for `.text`
  still emits `.recognizeText` (flag ignored); invalid selection cancels;
  image-snip effect arrays unchanged; hotkey default-combo + persisted-JSON
  fallback tests.
- **Shell (build + interactive smoke):** OCR a code/terminal region and
  paste — multi-line order preserved; HUD shows count; empty region (blank
  desktop) shows "No text found"; rebinding ⌃⌥6 in Settings works;
  image snip ⌃6 unaffected; recognition works with no network (Wi-Fi off
  spot-check validates on-device claim).

## Out of scope

- Saving recognized text to file (⌥ variant)
- Language pickers or recognition-level settings
- OCR of the full screen or of existing zoom/draw content
- QR/barcode detection
