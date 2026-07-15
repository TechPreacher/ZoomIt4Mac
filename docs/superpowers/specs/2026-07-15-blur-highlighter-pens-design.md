# ZoomIt4Mac Blur + Highlighter Pens — Design

Date: 2026-07-15
Status: Approved (brainstorming complete)
Branch: `feature/blur-highlighter-pens` (off `main` @ 6f86706)

## Goal

Two new draw-mode pens: **highlighter** (translucent marker stroke) and **blur**
(Gaussian-blurred rectangle over the frozen snapshot — for hiding text/PII
during presentations). Blur works only where a frozen snapshot exists
(draw-on-zoom, draw-on-frozen-live-zoom).

## Decisions

| Topic | Decision |
|---|---|
| Activation | Sticky pen styles toggled by single keys while drawing: `H` = highlighter, `X` = blur. Same key again → normal pen. Any color key (R/G/B/O/Y/P) → sets the color AND returns to the normal pen |
| Blur shape | Rectangle drag only; shape modifiers (⇧/⌃/Tab) are ignored while the blur pen is active |
| Highlighter shape | Honors all existing shape modifiers (freehand, ⇧ line, ⌃ rect, ⌃⇧ arrow, Tab ellipse) drawn translucent |
| Highlighter look | Pen color at 40 % alpha, stroke width ×3 of the current pen width, `.multiply` blend (marker feel over light content), round caps |
| Blur look | `CIGaussianBlur`, radius 12 image points, edges clamped (`clampedToExtent`) so the blur doesn't fade to transparent at the rect border |
| Blur availability | Only when the draw context is frozen-backed (`ctx.zoom != nil`, incl. `fromLiveZoom`). `X` in plain draw or on a white/black board: `[.notifyCaptureFailure]` (beep + log), style unchanged |
| Boards | Entering whiteboard/blackboard (`W`/`K`) while the blur pen is active reverts the style to normal (the snapshot is hidden behind the board, so existing blur annotations are hidden too — consistent) |
| Persistence | None — pen style is per-session canvas state like `background`; no Settings change |
| Undo/erase | Free — highlights and blur rects are ordinary annotations in `AnnotationCanvas` |
| Exports | Free — ⌘S/⌘C capture the rendered screen, blur/highlight included |

## Core (`ZoomItCore`)

- **`PenStyle`** (new, in AnnotationCanvas.swift): `enum PenStyle: Equatable, Sendable { case normal, highlighter, blur }`; `AnnotationCanvas.penStyle: PenStyle = .normal` (var, like `background`).
- **`Annotation`** gains two cases:
  - **`indirect case highlighted(Annotation)`** — wraps any existing geometric case (stroke/line/arrow/rectangle/ellipse); the renderer draws the wrapped annotation with highlighter compositing (40 % alpha, ×3 width, multiply blend). One case covers every shape with no duplication. Wrapping `.text` or nesting `.highlighted` is never produced by the tracker and renders as the base annotation.
  - **`.blurRect(CGRect)`** — normalized rect in image space.
- **`ShapeTracker`**: init gains `style: PenStyle = .normal`. `finish()`/`preview()`: for `.highlighter`, wrap the normal result in `.highlighted(...)` (nil stays nil); for `.blur`, ignore `shape` and return `.blurRect(normalizedRect)` (nil when `current == start`). Width stored unchanged — the ×3 is a render-time property of `.highlighted`.
- **`KeyCommand`** gains `.toggleHighlighter`, `.toggleBlur`.
- **`SessionStateMachine.handleDraw`**:
  - `.keyCommand(.toggleHighlighter)`: `penStyle = penStyle == .highlighter ? .normal : .highlighter`, `[.render]`.
  - `.keyCommand(.toggleBlur)`: if `ctx.zoom == nil` → return `[.notifyCaptureFailure]` (state untouched). Else toggle `penStyle` blur/normal, `[.render]`.
  - `.keyCommand(.color(c))`: existing color set PLUS `penStyle = .normal`.
  - `.keyCommand(.whiteboard/.blackboard)`: existing toggle PLUS `if penStyle == .blur { penStyle = .normal }`.
  - Entering type (`T`) and returning: canvas travels in the context — style survives, fine.

## Shell

- **`SessionCoordinator.handleMouseDown`** (draw case): pass `ctx.canvas.penStyle` to `ShapeTracker(style:)`. `shapeKind(for:)` unchanged (blur ignores it inside the tracker).
- **Key routing** (`handleKeyDown`, draw block): `"h"` → `.keyCommand(.toggleHighlighter)`, `"x"` → `.keyCommand(.toggleBlur)`.
- **`OverlayContentView.draw(_:)`**:
  - `.highlighted(let base)`: `cg.saveGState(); cg.setAlpha(0.4); cg.setBlendMode(.multiply)`, draw `base` with width ×3 (strokes/lines/arrows/rects/ellipses via the existing `draw(_:in:)` switch — extract the width so the wrapper can scale it), restore.
  - `.blurRect(let rect)`: render via a small **`BlurCache`** helper (new type in OverlayContentView.swift): key = rect + snapshot identity (`ObjectIdentifier`-style pointer of the CGImage); value = blurred CGImage crop. Miss → crop snapshot to rect (points→pixels ×scale, Y-flip — same math as snip's `pixelCrop`, reuse `SnipGeometry.pixelCrop`), `CIGaussianBlur(radius: 12 × scale)` on `clampedToExtent`, crop back to the rect extent, cache. Draw the cached image into the rect. No snapshot for this screen → draw nothing (core guard makes this unreachable in practice).
  - Preview during drag: same path — the tracker's `.blurRect` preview hits the cache per unique rect; cache capped (NSCache, ~64 entries) so a long drag can't hoard memory.
  - Cache cleared when `snapshot` changes (didSet).
- **Cursor/UX**: no cursor change; the existing crosshair applies.
- **Shortcuts panel**: draw section rows — `H` "Highlighter pen (toggle)", `X` "Blur pen — drag a rectangle (frozen zoom only, toggle)". **README**: draw-table rows for `H`/`X`.

## Error handling

- `X` without a frozen snapshot: beep + log via existing `.notifyCaptureFailure` effect; pen unchanged.
- Blur render failure (CIFilter/CGImage nil): draw nothing, log once — annotation stays undoable.
- Degenerate blur rects can't reach the renderer (tracker returns nil for zero-size; `SnipGeometry.pixelCrop` returns nil for off-snapshot rects → skip draw).

## Testing

Core (Swift Testing):
- PenStyle toggling: H toggles on/off; X toggles on/off in zoom-backed draw; color key reverts style to normal and sets color; W/K revert blur (but not highlighter); exact effect arrays.
- X in plain draw (no zoom ctx) → `[.notifyCaptureFailure]`, style stays normal. Same from a board over zoom? — board over zoom keeps `ctx.zoom != nil` → allowed (blur annotation hidden behind board until board off; acceptable, documented).
- ShapeTracker with `.highlighter`: every ShapeKind wraps in `.highlighted`; nil-propagation (no-movement drags stay nil); `.blur` yields `.blurRect` with normalized rect for all four drag directions, nil on zero drag, modifiers ignored.
- `.highlighted`/`.blurRect` equality; canvas add/undo/eraseAll with mixed annotation kinds.
- Type-tool round trip preserves penStyle (enter/exit type keeps canvas.penStyle).

Shell: manual smoke — highlighter over text (translucency, marker feel, all five shapes), blur rect hides text in zoom + frozen-live-zoom, X in plain draw beeps, H/X toggling + color-key revert, undo/erase across mixed annotations, ⌘S/⌘C exports include blur/highlight, boards interaction.

## Out of scope

Freehand blur brush, adjustable blur radius/highlighter alpha in Settings, pixelate style, blur in plain (non-frozen) draw via on-demand capture, persistence of pen style across sessions.
